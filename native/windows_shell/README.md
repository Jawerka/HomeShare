# HomeShare Windows Shell Extension

COM context-menu handler that adds **HomeShare** with a dynamic peer submenu to Explorer.

## Build (Visual Studio 2022+)

```bat
cl /LD /EHsc /DUNICODE /D_UNICODE HomeShareShell.cpp /link /DEF:HomeShareShell.def ole32.lib shell32.lib shlwapi.lib winhttp.lib /OUT:HomeShareShell.dll
```

Or open `HomeShareShell.vcxproj` if provided by CI.

## Register

```bat
regsvr32 HomeShareShell.dll
```

Place `homeshare.exe` next to the DLL (same folder as used by `GetModuleFileName` of the DLL).

## Behaviour

1. On right-click, queries `http://127.0.0.1:47831/v1/peers/online` (250 ms timeout).
2. Builds submenu of online trusted peers.
3. On click, launches `homeshare.exe --send <paths> --target <peer_id>`.
4. If agent is down: shows «HomeShare не запущен».
