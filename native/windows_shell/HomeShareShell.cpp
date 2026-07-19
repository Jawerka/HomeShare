// HomeShareShell.cpp — Explorer context menu with dynamic peer submenu.
// Build: scripts/build-shell-dll.ps1

#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <strsafe.h>
#include <winhttp.h>
#include <cwctype>
#include <string>
#include <vector>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

static const int AGENT_TIMEOUT_MS = 250;
static const int AGENT_PORT = 47831;

// {A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}
static const CLSID CLSID_HomeShareMenu =
{ 0xa7f3c2e1, 0x9b4d, 0x4e8a, { 0xb1, 0xc0, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab } };

static const wchar_t kClsidKey[] =
    L"Software\\Classes\\CLSID\\{A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}";
static const wchar_t kClsidValue[] = L"{A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}";

// UI strings as \u escapes so source encoding never breaks Cyrillic.
static const wchar_t kMenuTitle[] =
    L"\x041E\x0442\x043F\x0440\x0430\x0432\x0438\x0442\x044C"
    L" \x0447\x0435\x0440\x0435\x0437 HomeShare";
static const wchar_t kNotRunning[] =
    L"HomeShare \x043D\x0435 \x0437\x0430\x043F\x0443\x0449\x0435\x043D";
static const wchar_t kOpenApp[] =
    L"\x041E\x0442\x043A\x0440\x044B\x0442\x044C HomeShare";
static const wchar_t kNoPeers[] =
    L"\x041D\x0435\x0442 \x0443\x0441\x0442\x0440\x043E\x0439\x0441\x0442\x0432"
    L" \x043E\x043D\x043B\x0430\x0439\x043D";
static const wchar_t kChoose[] =
    L"\x0412\x044B\x0431\x0440\x0430\x0442\x044C\x2026";

HINSTANCE g_hInst = nullptr;
LONG g_locks = 0;

struct PeerInfo {
  std::wstring id;
  std::wstring name;
};

enum class CmdKind { None, Peer, Choose, OpenApp };

struct CmdEntry {
  CmdKind kind;
  size_t peerIndex;
};

static std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
  std::wstring w(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
  return w;
}

static void SetRegSz(HKEY key, const wchar_t* name, const wchar_t* value) {
  RegSetValueExW(key, name, 0, REG_SZ, (const BYTE*)value,
                 (DWORD)((wcslen(value) + 1) * sizeof(wchar_t)));
}

static bool HttpGetPeers(std::vector<PeerInfo>& out) {
  HINTERNET hSession = WinHttpOpen(L"HomeShareShell/0.1",
    WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!hSession) return false;
  WinHttpSetTimeouts(hSession, AGENT_TIMEOUT_MS, AGENT_TIMEOUT_MS, AGENT_TIMEOUT_MS, AGENT_TIMEOUT_MS);

  HINTERNET hConnect = WinHttpConnect(hSession, L"127.0.0.1", AGENT_PORT, 0);
  if (!hConnect) { WinHttpCloseHandle(hSession); return false; }

  HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", L"/v1/peers/online",
    nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
  if (!hRequest) {
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return false;
  }

  BOOL ok = WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
    WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
  if (ok) ok = WinHttpReceiveResponse(hRequest, nullptr);
  if (!ok) {
    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return false;
  }

  std::string body;
  DWORD avail = 0;
  while (WinHttpQueryDataAvailable(hRequest, &avail) && avail > 0) {
    std::string chunk(avail, 0);
    DWORD read = 0;
    if (!WinHttpReadData(hRequest, &chunk[0], avail, &read)) break;
    chunk.resize(read);
    body += chunk;
  }

  WinHttpCloseHandle(hRequest);
  WinHttpCloseHandle(hConnect);
  WinHttpCloseHandle(hSession);

  // Minimal JSON scrape: "peer_id":"...","display_name":"..."
  size_t pos = 0;
  while (true) {
    size_t idKey = body.find("\"peer_id\"", pos);
    if (idKey == std::string::npos) break;
    size_t idColon = body.find(':', idKey);
    size_t idQ1 = body.find('"', idColon + 1);
    size_t idQ2 = body.find('"', idQ1 + 1);
    if (idQ1 == std::string::npos || idQ2 == std::string::npos) break;
    std::string id = body.substr(idQ1 + 1, idQ2 - idQ1 - 1);

    size_t nameKey = body.find("\"display_name\"", idQ2);
    if (nameKey == std::string::npos || nameKey > idQ2 + 200) {
      pos = idQ2 + 1;
      continue;
    }
    size_t nameColon = body.find(':', nameKey);
    size_t nQ1 = body.find('"', nameColon + 1);
    size_t nQ2 = body.find('"', nQ1 + 1);
    if (nQ1 == std::string::npos || nQ2 == std::string::npos) break;
    std::string name = body.substr(nQ1 + 1, nQ2 - nQ1 - 1);

    PeerInfo p;
    p.id = Utf8ToWide(id);
    p.name = Utf8ToWide(name);
    out.push_back(p);
    pos = nQ2 + 1;
  }
  return true;
}

static std::wstring GetExePath() {
  wchar_t path[MAX_PATH];
  DWORD n = GetModuleFileNameW(g_hInst, path, MAX_PATH);
  std::wstring dll(path, n);
  size_t slash = dll.find_last_of(L"\\/");
  std::wstring dir = (slash == std::wstring::npos) ? L"." : dll.substr(0, slash);
  return dir + L"\\homeshare.exe";
}

static bool LaunchHomeShare(const std::wstring& args) {
  std::wstring cmd = L"\"" + GetExePath() + L"\" " + args;
  STARTUPINFOW si = { sizeof(si) };
  PROCESS_INFORMATION pi = {};
  if (!CreateProcessW(nullptr, &cmd[0], nullptr, nullptr, FALSE,
                      0, nullptr, nullptr, &si, &pi)) {
    return false;
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return true;
}

static std::wstring QuotePaths(const std::vector<std::wstring>& files) {
  std::wstring s;
  for (auto& f : files) {
    s += L" \"";
    s += f;
    s += L"\"";
  }
  return s;
}

static bool MenuTextContains(const wchar_t* hay, const wchar_t* needle) {
  if (!hay || !needle || !*needle) return false;
  // Case-insensitive substring search.
  size_t nlen = wcslen(needle);
  for (const wchar_t* p = hay; *p; ++p) {
    size_t i = 0;
    while (i < nlen && p[i] &&
           towlower(p[i]) == towlower(needle[i])) {
      ++i;
    }
    if (i == nlen) return true;
  }
  return false;
}

/// Prefer insert just after the built-in "Send to" / "Отправить" item.
static UINT FindInsertIndexNearSendTo(HMENU hmenu, UINT fallback) {
  const wchar_t* needles[] = {
      L"\x041E\x0442\x043F\x0440\x0430\x0432\x0438\x0442\x044C",  // Отправить
      L"Send to",
      L"SendTo",
  };
  UINT count = GetMenuItemCount(hmenu);
  for (UINT i = 0; i < count; ++i) {
    wchar_t text[256] = {};
    MENUITEMINFOW mii = { sizeof(mii) };
    mii.fMask = MIIM_STRING | MIIM_FTYPE | MIIM_SUBMENU;
    mii.dwTypeData = text;
    mii.cch = 255;
    if (!GetMenuItemInfoW(hmenu, i, TRUE, &mii)) continue;
    if (mii.fType & MFT_SEPARATOR) continue;
    // Strip leading '&' accelerators for matching.
    const wchar_t* p = text;
    while (*p == L'&') ++p;
    for (const wchar_t* needle : needles) {
      if (MenuTextContains(p, needle)) {
        return i + 1;  // right after "Send to"
      }
    }
  }
  return fallback;
}

class HomeShareContextMenu : public IShellExtInit, public IContextMenu {
public:
  HomeShareContextMenu() : _ref(1) { InterlockedIncrement(&g_locks); }
  ~HomeShareContextMenu() { InterlockedDecrement(&g_locks); }

  IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;
    if (riid == IID_IUnknown || riid == IID_IShellExtInit) *ppv = (IShellExtInit*)this;
    else if (riid == IID_IContextMenu) *ppv = (IContextMenu*)this;
    else return E_NOINTERFACE;
    AddRef();
    return S_OK;
  }
  IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&_ref); }
  IFACEMETHODIMP_(ULONG) Release() {
    LONG c = InterlockedDecrement(&_ref);
    if (c == 0) delete this;
    return c;
  }

  IFACEMETHODIMP Initialize(PCIDLIST_ABSOLUTE, IDataObject* pdtobj, HKEY) {
    _files.clear();
    if (!pdtobj) return E_INVALIDARG;
    FORMATETC fe = { CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    STGMEDIUM stm = {};
    if (FAILED(pdtobj->GetData(&fe, &stm))) return E_FAIL;
    HDROP hdrop = (HDROP)GlobalLock(stm.hGlobal);
    if (hdrop) {
      UINT n = DragQueryFileW(hdrop, 0xFFFFFFFF, nullptr, 0);
      for (UINT i = 0; i < n; i++) {
        wchar_t buf[MAX_PATH];
        DragQueryFileW(hdrop, i, buf, MAX_PATH);
        _files.push_back(buf);
      }
      GlobalUnlock(stm.hGlobal);
    }
    ReleaseStgMedium(&stm);
    return _files.empty() ? E_FAIL : S_OK;
  }

  IFACEMETHODIMP QueryContextMenu(HMENU hmenu, UINT indexMenu, UINT idCmdFirst,
                                  UINT idCmdLast, UINT uFlags) {
    if (uFlags & CMF_DEFAULTONLY) return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);

    _peers.clear();
    _cmds.clear();
    bool agentOk = HttpGetPeers(_peers);

    HMENU sub = CreatePopupMenu();
    UINT id = idCmdFirst;

    if (!agentOk) {
      AppendMenuW(sub, MF_STRING | MF_GRAYED, id, kNotRunning);
      _cmds.push_back({ CmdKind::None, 0 });
      id++;
      AppendMenuW(sub, MF_STRING, id, kOpenApp);
      _cmds.push_back({ CmdKind::OpenApp, 0 });
      id++;
    } else if (_peers.empty()) {
      AppendMenuW(sub, MF_STRING | MF_GRAYED, id, kNoPeers);
      _cmds.push_back({ CmdKind::None, 0 });
      id++;
      AppendMenuW(sub, MF_STRING, id, kChoose);
      _cmds.push_back({ CmdKind::Choose, 0 });
      id++;
    } else {
      for (size_t i = 0; i < _peers.size(); i++) {
        AppendMenuW(sub, MF_STRING, id, _peers[i].name.c_str());
        _cmds.push_back({ CmdKind::Peer, i });
        id++;
      }
      AppendMenuW(sub, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(sub, MF_STRING, id, kChoose);
      _cmds.push_back({ CmdKind::Choose, 0 });
      id++;
    }

    // Place next to the built-in "Send to" / "Отправить" item.
    UINT insertAt = FindInsertIndexNearSendTo(hmenu, indexMenu);
    const UINT menuCount = GetMenuItemCount(hmenu);
    if (insertAt > menuCount) insertAt = menuCount;

    MENUITEMINFOW mii = { sizeof(mii) };
    mii.fMask = MIIM_SUBMENU | MIIM_STRING | MIIM_FTYPE;
    mii.fType = MFT_STRING;
    mii.hSubMenu = sub;
    mii.dwTypeData = const_cast<LPWSTR>(kMenuTitle);
    InsertMenuItemW(hmenu, insertAt, TRUE, &mii);

    return MAKE_HRESULT(SEVERITY_SUCCESS, FACILITY_NULL, id - idCmdFirst);
  }

  IFACEMETHODIMP InvokeCommand(CMINVOKECOMMANDINFO* pici) {
    if (!pici) return E_INVALIDARG;
    if (HIWORD(pici->lpVerb) != 0) return E_INVALIDARG;
    UINT idx = LOWORD(pici->lpVerb);
    if (idx >= _cmds.size()) return E_INVALIDARG;
    const CmdEntry& cmd = _cmds[idx];
    if (cmd.kind == CmdKind::None) return E_FAIL;

    if (cmd.kind == CmdKind::OpenApp) {
      return LaunchHomeShare(L"--show") ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    }
    if (cmd.kind == CmdKind::Choose) {
      // Show picker UI (no --background).
      std::wstring args = L"--send" + QuotePaths(_files);
      return LaunchHomeShare(args) ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    }
    if (cmd.kind == CmdKind::Peer) {
      if (cmd.peerIndex >= _peers.size()) return E_INVALIDARG;
      // Stay in tray: --background + --target.
      std::wstring args = L"--background --send" + QuotePaths(_files);
      args += L" --target ";
      args += _peers[cmd.peerIndex].id;
      return LaunchHomeShare(args) ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    }
    return E_INVALIDARG;
  }

  IFACEMETHODIMP GetCommandString(UINT_PTR, UINT, UINT*, CHAR*, UINT) {
    return E_NOTIMPL;
  }

private:
  LONG _ref;
  std::vector<std::wstring> _files;
  std::vector<PeerInfo> _peers;
  std::vector<CmdEntry> _cmds;
};

class ClassFactory : public IClassFactory {
public:
  ClassFactory() : _ref(1) { InterlockedIncrement(&g_locks); }
  ~ClassFactory() { InterlockedDecrement(&g_locks); }

  IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    *ppv = nullptr;
    if (riid == IID_IUnknown || riid == IID_IClassFactory) *ppv = (IClassFactory*)this;
    else return E_NOINTERFACE;
    AddRef();
    return S_OK;
  }
  IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&_ref); }
  IFACEMETHODIMP_(ULONG) Release() {
    LONG c = InterlockedDecrement(&_ref);
    if (c == 0) delete this;
    return c;
  }
  IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) {
    if (outer) return CLASS_E_NOAGGREGATION;
    auto* obj = new (std::nothrow) HomeShareContextMenu();
    if (!obj) return E_OUTOFMEMORY;
    HRESULT hr = obj->QueryInterface(riid, ppv);
    obj->Release();
    return hr;
  }
  IFACEMETHODIMP LockServer(BOOL lock) {
    if (lock) InterlockedIncrement(&g_locks);
    else InterlockedDecrement(&g_locks);
    return S_OK;
  }
private:
  LONG _ref;
};

extern "C" BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_hInst = h;
    DisableThreadLibraryCalls(h);
  }
  return TRUE;
}

STDAPI DllCanUnloadNow() {
  return g_locks == 0 ? S_OK : S_FALSE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
  if (rclsid != CLSID_HomeShareMenu) return CLASS_E_CLASSNOTAVAILABLE;
  auto* f = new (std::nothrow) ClassFactory();
  if (!f) return E_OUTOFMEMORY;
  HRESULT hr = f->QueryInterface(riid, ppv);
  f->Release();
  return hr;
}

STDAPI DllRegisterServer() {
  wchar_t dllPath[MAX_PATH];
  GetModuleFileNameW(g_hInst, dllPath, MAX_PATH);
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kClsidKey, 0, nullptr, 0, KEY_WRITE,
                      nullptr, &key, nullptr) == ERROR_SUCCESS) {
    SetRegSz(key, nullptr, L"HomeShare Context Menu");
    HKEY inproc = nullptr;
    if (RegCreateKeyExW(key, L"InprocServer32", 0, nullptr, 0, KEY_WRITE,
                        nullptr, &inproc, nullptr) == ERROR_SUCCESS) {
      SetRegSz(inproc, nullptr, dllPath);
      SetRegSz(inproc, L"ThreadingModel", L"Apartment");
      RegCloseKey(inproc);
    }
    RegCloseKey(key);
  }

  // Remove static verb fallback so only the COM submenu appears.
  RegDeleteTreeW(HKEY_CURRENT_USER, L"Software\\Classes\\*\\shell\\HomeShare");
  RegDeleteTreeW(HKEY_CURRENT_USER, L"Software\\Classes\\Directory\\shell\\HomeShare");

  if (RegCreateKeyExW(HKEY_CURRENT_USER,
        L"Software\\Classes\\*\\shellex\\ContextMenuHandlers\\HomeShare",
        0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    SetRegSz(key, nullptr, kClsidValue);
    RegCloseKey(key);
  }
  if (RegCreateKeyExW(HKEY_CURRENT_USER,
        L"Software\\Classes\\Directory\\shellex\\ContextMenuHandlers\\HomeShare",
        0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    SetRegSz(key, nullptr, kClsidValue);
    RegCloseKey(key);
  }
  return S_OK;
}

STDAPI DllUnregisterServer() {
  RegDeleteTreeW(HKEY_CURRENT_USER, kClsidKey);
  RegDeleteTreeW(HKEY_CURRENT_USER,
      L"Software\\Classes\\*\\shellex\\ContextMenuHandlers\\HomeShare");
  RegDeleteTreeW(HKEY_CURRENT_USER,
      L"Software\\Classes\\Directory\\shellex\\ContextMenuHandlers\\HomeShare");
  return S_OK;
}
