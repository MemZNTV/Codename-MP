package funkin.backend.utils.native;

#if windows
import funkin.backend.utils.NativeAPI.FileAttribute;
import funkin.backend.utils.NativeAPI.MessageBoxIcon;
@:buildXml('
<target id="haxe">
	<lib name="dwmapi.lib" if="windows" />
	<lib name="shell32.lib" if="windows" />
	<lib name="gdi32.lib" if="windows" />
	<lib name="ole32.lib" if="windows" />
	<lib name="uxtheme.lib" if="windows" />
</target>
')

// majority is taken from Microsoft's doc
@:cppFileCode('
#include "mmdeviceapi.h"
#include "combaseapi.h"
#include <iostream>
#include <Windows.h>
#include <cstdio>
#include <tchar.h>
#include <dwmapi.h>
#include <winuser.h>
#include <Shlobj.h>
#include <wingdi.h>
#include <shellapi.h>
#include <uxtheme.h>
#include <psapi.h>
#include <vector>
#include <string>

// windows that minimizeOtherWindows() minimized, so restoreMinimizedWindows() can bring back exactly those
static std::vector<HWND> g_minimizedWindows;

static BOOL CALLBACK minimizeEnumProc(HWND hwnd, LPARAM lParam) {
	if (hwnd == (HWND)lParam || !IsWindowVisible(hwnd) || IsIconic(hwnd)) return TRUE;
	if (GetWindowTextLengthW(hwnd) == 0) return TRUE;
	if (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) return TRUE;

	// never touch the desktop / taskbar themselves
	wchar_t cls[64] = {0};
	GetClassNameW(hwnd, cls, 63);
	if (wcscmp(cls, L"Shell_TrayWnd") == 0 || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0 ||
		wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0) return TRUE;

	// skip "cloaked" windows (invisible UWP shells that still report as visible)
	BOOL cloaked = FALSE;
	DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
	if (cloaked) return TRUE;

	g_minimizedWindows.push_back(hwnd);
	ShowWindow(hwnd, SW_SHOWMINNOACTIVE);
	return TRUE;
}
')
@:dox(hide)
final class Windows {

	@:functionCode('
		int darkMode = enable ? 1 : 0;

		HWND window = FindWindowA(NULL, title.c_str());
		// Look for child windows if top level is not found
		if (window == NULL) window = FindWindowExA(GetActiveWindow(), NULL, NULL, title.c_str());
		// If still not found, try to get the active window
		if (window == NULL) window = GetActiveWindow();
		if (window == NULL) return;

		if (S_OK != DwmSetWindowAttribute(window, 19, &darkMode, sizeof(darkMode))) {
			DwmSetWindowAttribute(window, 20, &darkMode, sizeof(darkMode));
		}
		UpdateWindow(window);
	')
	public static function setDarkMode(title:String, enable:Bool) {}

	@:functionCode('
	HWND window = FindWindowA(NULL, title.c_str());
	if (window == NULL) window = FindWindowExA(GetActiveWindow(), NULL, NULL, title.c_str());
	if (window == NULL) window = GetActiveWindow();
	if (window == NULL) return;

	COLORREF finalColor;
	if(color[0] == -1 && color[1] == -1 && color[2] == -1 && color[3] == -1) { // bad fix, I know :sob:
		finalColor = 0xFFFFFFFF; // Default border
	} else if(color[3] == 0) {
		finalColor = 0xFFFFFFFE; // No border (must have setBorder as true)
	} else {
		finalColor = RGB(color[0], color[1], color[2]); // Use your custom color
	}

	if(setHeader) DwmSetWindowAttribute(window, 35, &finalColor, sizeof(COLORREF));
	if(setBorder) DwmSetWindowAttribute(window, 34, &finalColor, sizeof(COLORREF));

	UpdateWindow(window);
	')
	public static function setWindowBorderColor(title:String, color:Array<Int>, setHeader:Bool = true, setBorder:Bool = true) {}

	@:functionCode('
	HWND window = FindWindowA(NULL, title.c_str());
	if (window == NULL) window = FindWindowExA(GetActiveWindow(), NULL, NULL, title.c_str());
	if (window == NULL) window = GetActiveWindow();
	if (window == NULL) return;

	COLORREF finalColor;
	if(color[0] == -1 && color[1] == -1 && color[2] == -1 && color[3] == -1) { // bad fix, I know :sob:
		finalColor = 0xFFFFFFFF; // Default border
	} else {
		finalColor = RGB(color[0], color[1], color[2]); // Use your custom color
	}

	DwmSetWindowAttribute(window, 36, &finalColor, sizeof(COLORREF));
	UpdateWindow(window);
	')
	public static function setWindowTitleColor(title:String, color:Array<Int>) {}

	@:functionCode('
	HWND window = GetConsoleWindow();
	HICON smallIcon = (HICON) LoadImage(NULL, path, IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
	HICON icon = (HICON) LoadImage(NULL, path, IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
	SendMessage(window, WM_SETICON, ICON_SMALL, (LPARAM)smallIcon);
	SendMessage(window, WM_SETICON, ICON_BIG, (LPARAM)icon);    
	')
	public static function setWindowIcon(path:String) {}


	@:functionCode('
	// https://stackoverflow.com/questions/15543571/allocconsole-not-displaying-cout

	if (!AllocConsole())
		return;

	freopen("CONIN$", "r", stdin);
	freopen("CONOUT$", "w", stdout);
	freopen("CONOUT$", "w", stderr);

	SetConsoleOutputCP(65001);
	SetConsoleCP(65001);
	')
	public static function allocConsole() {
	}

	@:functionCode('
		return GetFileAttributes(path);
	')
	public static function getFileAttributes(path:String):FileAttribute
	{
		return NORMAL;
	}

	@:functionCode('
		return SetFileAttributes(path, attrib);
	')
	public static function setFileAttributes(path:String, attrib:FileAttribute):Int
	{
		return 0;
	}


	@:functionCode('
		HANDLE console = GetStdHandle(STD_OUTPUT_HANDLE);
		SetConsoleTextAttribute(console, color);
	')
	public static function setConsoleColors(color:Int) {

	}

	@:functionCode('
		system("CLS");
		std::cout<< "" <<std::flush;
	')
	public static function clearScreen() {

	}


	@:functionCode('
		MessageBox(GetActiveWindow(), message, caption, icon | MB_SETFOREGROUND);
	')
	public static function showMessageBox(caption:String, message:String, icon:MessageBoxIcon = MSG_WARNING) {

	}

	@:functionCode('
		SetProcessDPIAware();
	')
	public static function registerAsDPICompatible() {}

	@:functionCode("
		// simple but effective code
		unsigned long long allocatedRAM = 0;
		GetPhysicallyInstalledSystemMemory(&allocatedRAM);
		return (allocatedRAM / 1024);
	")
	public static function getTotalRam():Float
	{
		return 0;
	}

	@:functionCode("
		PROCESS_MEMORY_COUNTERS_EX pmc;
		if (GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS*)&pmc, sizeof(pmc))) {
			return (double)pmc.WorkingSetSize;
		}
		return 0.0;
	")
	public static function getCurrentProcessMemory():Float
	{
		return 0;
	}
	// ---- desktop effects (used by mods that take over the desktop, like Mario's Madness' Paranoia) ----

	@:functionCode('
		const wchar_t* wide = path.wchar_str();
		BOOL ok = SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, (PVOID)wide, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
		return ok ? 0 : (int)GetLastError();
	')
	public static function setWallpaper(path:String):Int {
		return -1;
	}

	@:functionCode('
		HWND window = FindWindowA(NULL, title.c_str());
		if (window == NULL) window = GetActiveWindow();
		if (window == NULL) return;
		SetWindowPos(window, enable ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
	')
	public static function setWindowTopmost(title:String, enable:Bool) {}

	@:functionCode('
		wchar_t buffer[MAX_PATH] = {0};
		SystemParametersInfoW(SPI_GETDESKWALLPAPER, MAX_PATH, buffer, 0);
		return ::String::create(buffer);
	')
	public static function getWallpaper():String {
		return "";
	}

	@:functionCode('
		HWND self = FindWindowA(NULL, title.c_str());
		if (self == NULL) self = GetActiveWindow();
		g_minimizedWindows.clear();
		EnumWindows(minimizeEnumProc, (LPARAM)self);
		return (int)g_minimizedWindows.size();
	')
	public static function minimizeOtherWindows(title:String):Int {
		return 0;
	}

	@:functionCode('
		for (size_t i = 0; i < g_minimizedWindows.size(); i++)
			if (IsWindow(g_minimizedWindows[i])) ShowWindow(g_minimizedWindows[i], SW_SHOWNOACTIVATE);
		g_minimizedWindows.clear();
	')
	public static function restoreMinimizedWindows() {}

	// SetProcessInformation is looked up at runtime (Windows 8+; the throttling flags need Windows 10 1709+),
	// so this builds against any SDK and silently does nothing on older systems.
	@:functionCode('
		typedef struct { ULONG Version; ULONG ControlMask; ULONG StateMask; } CnePowerThrottlingState;
		typedef BOOL (WINAPI *CneSetProcessInformation)(HANDLE, int, LPVOID, DWORD);
		HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
		CneSetProcessInformation setInfo = kernel ? (CneSetProcessInformation)GetProcAddress(kernel, "SetProcessInformation") : NULL;
		if (setInfo != NULL) {
			CnePowerThrottlingState state;
			state.Version = 1;                                // PROCESS_POWER_THROTTLING_CURRENT_VERSION
			state.ControlMask = enable ? (0x1 | 0x4) : 0;     // EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION, 0 = let Windows decide again
			state.StateMask = 0;                              // 0 = never throttle what ControlMask names
			setInfo(GetCurrentProcess(), 4, &state, sizeof(state)); // 4 = ProcessPowerThrottling
		}
		SetThreadExecutionState(enable ? (ES_CONTINUOUS | ES_SYSTEM_REQUIRED) : ES_CONTINUOUS);
	')
	public static function setBackgroundKeepAlive(enable:Bool) {}

	// every taskbar: the main one plus the ones on other monitors
	@:functionCode('
		HWND tray = FindWindowW(L"Shell_TrayWnd", NULL);
		if (tray != NULL) ShowWindow(tray, show ? SW_SHOWNA : SW_HIDE);
		HWND other = NULL;
		while ((other = FindWindowExW(NULL, other, L"Shell_SecondaryTrayWnd", NULL)) != NULL)
			ShowWindow(other, show ? SW_SHOWNA : SW_HIDE);
		return tray != NULL ? 0 : -1;
	')
	public static function setTaskbarVisible(show:Bool):Int {
		return -3;
	}

	// the desktop icons are a list view inside SHELLDLL_DefView, which lives under Progman (or under a WorkerW
	// window when a wallpaper slideshow is running)
	@:functionCode('
		HWND progman = FindWindowW(L"Progman", NULL);
		HWND defView = progman != NULL ? FindWindowExW(progman, NULL, L"SHELLDLL_DefView", NULL) : NULL;
		if (defView == NULL) {
			HWND worker = NULL;
			while ((worker = FindWindowExW(NULL, worker, L"WorkerW", NULL)) != NULL) {
				defView = FindWindowExW(worker, NULL, L"SHELLDLL_DefView", NULL);
				if (defView != NULL) break;
			}
		}
		if (defView == NULL) return -1;
		HWND icons = FindWindowExW(defView, NULL, L"SysListView32", NULL);
		if (icons == NULL) return -2;
		ShowWindow(icons, show ? SW_SHOWNA : SW_HIDE);
		return 0;
	')
	public static function setDesktopIconsVisible(show:Bool):Int {
		return -3;
	}

	@:functionCode('
		HWND window = FindWindowA(NULL, title.c_str());
		if (window == NULL) window = GetActiveWindow();
		if (window == NULL) return -1; // no window found at all

		LONG_PTR ex = GetWindowLongPtrW(window, GWL_EXSTYLE);
		if (enable) {
			SetWindowLongPtrW(window, GWL_EXSTYLE, ex | WS_EX_LAYERED);
			BOOL ok = SetLayeredWindowAttributes(window, RGB(r, g, b), 0, LWA_COLORKEY);
			return ok ? 0 : (int)GetLastError();
		} else {
			SetWindowLongPtrW(window, GWL_EXSTYLE, ex & ~WS_EX_LAYERED);
			return 0;
		}
	')
	public static function setWindowColorKey(title:String, r:Int, g:Int, b:Int, enable:Bool):Int {
		return -2;
	}

	// Captures a specific screen region (in virtual-desktop coordinates - same space as a Lime
	// Display's bounds) to a 24-bit BMP file. Used by mods that fake window transparency by showing a
	// snapshot of the desktop underneath instead of relying on real (unreliable, on an OpenGL-rendered
	// window) OS-level compositing. Pass the target monitor\'s own bounds, not the whole virtual screen
	// spanning every monitor, or the capture will span all of them squished into one image.
	@:functionCode('
		if (w <= 0 || h <= 0) return -1;

		HDC hScreen = GetDC(NULL);
		if (hScreen == NULL) return -2;
		HDC hMemDC = CreateCompatibleDC(hScreen);
		HBITMAP hBitmap = CreateCompatibleBitmap(hScreen, w, h);
		HBITMAP hOld = (HBITMAP)SelectObject(hMemDC, hBitmap);
		BOOL blitOk = BitBlt(hMemDC, 0, 0, w, h, hScreen, x, y, SRCCOPY | CAPTUREBLT);
		SelectObject(hMemDC, hOld);

		if (!blitOk) {
			DeleteObject(hBitmap);
			DeleteDC(hMemDC);
			ReleaseDC(NULL, hScreen);
			return -3;
		}

		BITMAPINFOHEADER bi = {0};
		bi.biSize = sizeof(BITMAPINFOHEADER);
		bi.biWidth = w;
		bi.biHeight = h;
		bi.biPlanes = 1;
		bi.biBitCount = 24;
		bi.biCompression = BI_RGB;

		DWORD rowSize = ((w * bi.biBitCount + 31) / 32) * 4;
		DWORD dwBmpSize = rowSize * h;

		HANDLE hDIB = GlobalAlloc(GHND, dwBmpSize);
		if (hDIB == NULL) {
			DeleteObject(hBitmap);
			DeleteDC(hMemDC);
			ReleaseDC(NULL, hScreen);
			return -4;
		}
		char* lpbitmap = (char*)GlobalLock(hDIB);
		GetDIBits(hMemDC, hBitmap, 0, (UINT)h, lpbitmap, (BITMAPINFO*)&bi, DIB_RGB_COLORS);

		BITMAPFILEHEADER bmfHeader = {0};
		bmfHeader.bfType = 0x4D42; // \'BM\'
		bmfHeader.bfOffBits = (DWORD)sizeof(BITMAPFILEHEADER) + (DWORD)sizeof(BITMAPINFOHEADER);
		bmfHeader.bfSize = bmfHeader.bfOffBits + dwBmpSize;

		const wchar_t* wide = path.wchar_str();
		HANDLE hFile = CreateFileW(wide, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		int result = 0;
		if (hFile == INVALID_HANDLE_VALUE) {
			result = -5;
		} else {
			DWORD written = 0;
			WriteFile(hFile, (LPCVOID)&bmfHeader, sizeof(BITMAPFILEHEADER), &written, NULL);
			WriteFile(hFile, (LPCVOID)&bi, sizeof(BITMAPINFOHEADER), &written, NULL);
			WriteFile(hFile, (LPCVOID)lpbitmap, dwBmpSize, &written, NULL);
			CloseHandle(hFile);
		}

		GlobalUnlock(hDIB);
		GlobalFree(hDIB);
		DeleteObject(hBitmap);
		DeleteDC(hMemDC);
		ReleaseDC(NULL, hScreen);
		return result;
	')
	public static function captureScreenToFile(path:String, x:Int, y:Int, w:Int, h:Int):Int {
		return -9;
	}
}
#end