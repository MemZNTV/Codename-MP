package funkin.backend.utils;

import haxe.macro.Expr.Case;
import openfl.ui.Mouse;
import openfl.ui.MouseCursor;
import funkin.backend.utils.native.*;
import flixel.util.typeLimit.OneOfTwo;
import flixel.util.typeLimit.OneOfThree;
import flixel.util.FlxColor;

/**
 * Class for functions that talk to a lower level than haxe, such as message boxes, and more.
 * Some functions might not have effect on some platforms.
 */
class NativeAPI {
	@:dox(hide) public static function registerAsDPICompatible() {
		#if windows
		Windows.registerAsDPICompatible();
		#end
	}

	/**
	 * Allocates a new console. The console will automatically be opened
	 */
	public static function allocConsole() {
		#if windows
		Windows.allocConsole();
		Windows.clearScreen();
		#end
	}

	/**
	 * Gets the specified file's (or folder) attributes.
	 */
	public static function getFileAttributesRaw(path:String, useAbsolute:Bool = true):Int {
		#if windows
		if(useAbsolute) path = sys.FileSystem.absolutePath(path);
		return Windows.getFileAttributes(path);
		#else
		return -1;
		#end
	}

	/**
	 * Gets the specified file's (or folder) attributes and passes it to `FileAttributeWrapper`.
	 */
	public static function getFileAttributes(path:String, useAbsolute:Bool = true):FileAttributeWrapper {
		return new FileAttributeWrapper(getFileAttributesRaw(path, useAbsolute));
	}

	/**
	 * Sets the specified file's (or folder) attributes. If it fails, the return value is `0`.
	 */
	public static function setFileAttributes(path:String, attrib:OneOfThree<NativeAPI.FileAttribute, FileAttributeWrapper, Int>, useAbsolute:Bool = true):Int {
		#if windows
		if(useAbsolute) path = sys.FileSystem.absolutePath(path);
		return Windows.setFileAttributes(path, attrib is FileAttributeWrapper ? cast(attrib, FileAttributeWrapper).getValue() : cast(attrib, Int));
		#else
		return 0;
		#end
	}

	/**
	 * Removes from the specified file's (or folder) one (or more) specific attribute.
	 */
	public static function addFileAttributes(path:String, attrib:OneOfTwo<NativeAPI.FileAttribute, Int>, useAbsolute:Bool = true):Int {
		#if windows
		return setFileAttributes(path, getFileAttributesRaw(path, useAbsolute) | cast(attrib, Int), useAbsolute);
		#else
		return 0;
		#end
	}

	/**
	 * Removes from the specified file's (or folder) one (or more) specific attribute.
	 */
	public static function removeFileAttributes(path:String, attrib:OneOfTwo<NativeAPI.FileAttribute, Int>, useAbsolute:Bool = true):Int {
		#if windows
		return setFileAttributes(path, getFileAttributesRaw(path, useAbsolute) & ~cast(attrib, Int), useAbsolute);
		#else
		return 0;
		#end
	}

	/**
	 * WINDOW COLOR MODE FUNCTIONS.
	 */

	/**
	 * Sets the desktop wallpaper to the image at `path` (absolute path to a .bmp/.jpg/.png).
	 * Windows only. Remember to restore the old one (`getWallpaper` before changing it).
	 */
	public static function setWallpaper(path:String):Int {
		#if windows
		return Windows.setWallpaper(path);
		#else
		return -1;
		#end
	}

	/**
	 * Sets whether the game window stays above every other window (topmost z-order), regardless of
	 * focus. Used by mods that take over the desktop (like Mario's Madness' Paranoia) so the window
	 * can't get buried behind the taskbar or other apps while it's simulating the desktop.
	 * @param title Window title to affect. Defaults to the game's own window.
	 * @param enable `true` to pin the window on top, `false` to return it to normal z-order.
	 */
	public static function setWindowTopmost(?title:String, enable:Bool = true) {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		Windows.setWindowTopmost(title, enable);
		#end
	}

	/**
	 * Keeps the game running at full speed while it's in the background: opts the process out of
	 * Windows' background power throttling (EcoQoS and the coarse timer given to hidden windows) and
	 * stops the PC from going to sleep. Used while connected to a multiplayer server.
	 * @param enable `true` to keep running, `false` to hand control back to Windows.
	 */
	public static function setBackgroundKeepAlive(enable:Bool) {
		#if windows
		Windows.setBackgroundKeepAlive(enable);
		#end
	}

	/**
	 * Hides or shows the Windows taskbar (on every monitor). Used by mods that take over the desktop, like
	 * VS Rewrite's Trinity. Always show it again afterwards (a mod should do it in its `destroy`).
	 * Returns 0 on success, a negative number if the taskbar couldn't be found or outside of Windows.
	 */
	public static function setTaskbarVisible(show:Bool):Int {
		#if windows
		return Windows.setTaskbarVisible(show);
		#else
		return -3;
		#end
	}

	/**
	 * Hides or shows the icons on the Windows desktop (the wallpaper stays). Always show them again afterwards.
	 * Returns 0 on success, a negative number if they couldn't be found or outside of Windows.
	 */
	public static function setDesktopIconsVisible(show:Bool):Int {
		#if windows
		return Windows.setDesktopIconsVisible(show);
		#else
		return -3;
		#end
	}

	/**
	 * Gets the path of the current desktop wallpaper. Returns an empty string outside of Windows.
	 */
	public static function getWallpaper():String {
		#if windows
		return Windows.getWallpaper();
		#else
		return "";
		#end
	}

	/**
	 * Minimizes every other window on the desktop (not the taskbar or the game), so only the desktop shows.
	 * Bring them back with `restoreMinimizedWindows`. Minimized (not hidden) on purpose: if the game ever crashes
	 * in between, the windows are still in the taskbar.
	 * @return How many windows were minimized.
	 */
	public static function minimizeOtherWindows(?title:String):Int {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		return Windows.minimizeOtherWindows(title);
		#else
		return 0;
		#end
	}

	/**
	 * Restores the windows minimized by the last `minimizeOtherWindows` call.
	 */
	public static function restoreMinimizedWindows() {
		#if windows
		Windows.restoreMinimizedWindows();
		#end
	}

	/**
	 * Makes every pixel of the game window with exactly this color transparent (or turns that off).
	 * Windows only.
	 */
	public static function setWindowColorKey(title:String, color:FlxColor, enable:Bool = true):Int {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		return Windows.setWindowColorKey(title, color.red, color.green, color.blue, enable);
		#else
		return -3;
		#end
	}

	/**
	 * Captures a screen region (virtual-desktop coordinates, same space as `Window.display.bounds`) to a
	 * 24-bit BMP file at `path`. Used by mods that fake window transparency by showing a snapshot of the
	 * desktop underneath instead of relying on real OS-level compositing. Pass the target monitor's own
	 * bounds, not the whole virtual screen, or multi-monitor setups get every monitor squished into one
	 * image. Returns 0 on success, a negative error code otherwise. Windows only.
	 */
	public static function captureScreenToFile(path:String, x:Int, y:Int, w:Int, h:Int):Int {
		#if windows
		return Windows.captureScreenToFile(path, x, y, w, h);
		#else
		return -9;
		#end
	}

	/**
	 * Switch the window's color mode to dark or light mode.
	 */
	public static function setDarkMode(title:String, enable:Bool) {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		Windows.setDarkMode(title, enable);
		#end
	}

	/**
	 * Switch the window's color to any color.
	 *
	 * WARNING: This is exclusive to windows 11 users, unfortunately.
	 *
	 * NOTE: Setting the color to 0x00000000 (FlxColor.TRANSPARENT) will set the border (must have setBorder on) invisible.
	 */
	public static function setWindowBorderColor(title:String, color:FlxColor, setHeader:Bool = true, setBorder:Bool = true) {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		Windows.setWindowBorderColor(title, [color.red, color.green, color.blue, color.alpha], setHeader, setBorder);
		#end
	}

	/**
	 * Resets the window's border color to the default one.
	 *
	 * WARNING: This is exclusive to windows 11 users, unfortunately.
	**/
	public static function resetWindowBorderColor(title:String, setHeader:Bool = true, setBorder:Bool = true) {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		Windows.setWindowBorderColor(title, [-1, -1, -1, -1], setHeader, setBorder);
		#end
	}

	/**
	 * Switch the window's title text to any color.
	 *
	 * WARNING: This is exclusive to windows 11 users, unfortunately.
	 */
	public static function setWindowTitleColor(title:String, color:FlxColor) {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		Windows.setWindowTitleColor(title, [color.red, color.green, color.blue, color.alpha]);
		#end
	}

	/**
	 * Resets the window's title color to the default one.
	 *
	 * WARNING: This is exclusive to windows 11 users, unfortunately.
	**/
	public static function resetWindowTitleColor(title:String) {
		#if windows
		if(title == null) title = lime.app.Application.current.window.title;
		Windows.setWindowTitleColor(title, [-1, -1, -1, -1]);
		#end
	}

	/**
	 * Forces the window header to redraw, causes a small visual jitter so use it sparingly.
	 */
	public static function redrawWindowHeader() {
		#if windows
		flixel.FlxG.stage.window.borderless = true;
		flixel.FlxG.stage.window.borderless = false;
		#end
	}

	/**
	 * Can be used to check if your using a specific version of an OS (or if your using a certain OS).
	 */
	public static function hasVersion(vers:String)
		return lime.system.System.platformLabel.toLowerCase().indexOf(vers.toLowerCase()) != -1;

	/**
	 * Shows a message box
	 */
	public static function showMessageBox(caption:String, message:String, icon:MessageBoxIcon = MSG_WARNING) {
		#if windows
		Windows.showMessageBox(caption, message, icon);
		#else
		lime.app.Application.current.window.alert(message, caption);
		#end
	}

	/**
	 * Sets the console colors
	 */
	public static function setConsoleColors(foregroundColor:ConsoleColor = NONE, ?backgroundColor:ConsoleColor = NONE) {
		if(Main.noTerminalColor) return;

		#if sys
		Sys.print("\x1b[0m");
		if(foregroundColor != NONE)
			Sys.print("\x1b[" + Std.int(consoleColorToANSI(foregroundColor)) + "m");
		if(backgroundColor != NONE)
			Sys.print("\x1b[" + Std.int(consoleColorToANSI(backgroundColor) + 10) + "m");
		#end
	}

	/**
	 * Set cursor icon.
	**/
	public static function setCursorIcon(icon:CodeCursor) {
		#if (mac && cpp)
		Mac.setMouseCursorIcon(cast icon);
		#else
		Mouse.cursor = icon.toOpenFL();
		#end
	}

	public static function consoleColorToANSI(color:ConsoleColor) {
		return switch(color) {
			case BLACK:			30;
			case DARKBLUE:		34;
			case DARKGREEN:		32;
			case DARKCYAN:		36;
			case DARKRED:		31;
			case DARKMAGENTA:	35;
			case DARKYELLOW:	33;
			case LIGHTGRAY:		37;
			case GRAY:			90;
			case BLUE:			94;
			case GREEN:			92;
			case CYAN:			96;
			case RED:			91;
			case MAGENTA:		95;
			case YELLOW:		93;
			case WHITE | _:		97;
		}
	}

	public static function consoleColorToOpenFL(color:ConsoleColor) {
		return switch(color) {
			case BLACK:			0xFF000000;
			case DARKBLUE:		0xFF000088;
			case DARKGREEN:		0xFF008800;
			case DARKCYAN:		0xFF008888;
			case DARKRED:		0xFF880000;
			case DARKMAGENTA:	0xFF880000;
			case DARKYELLOW:	0xFF888800;
			case LIGHTGRAY:		0xFFBBBBBB;
			case GRAY:			0xFF888888;
			case BLUE:			0xFF0000FF;
			case GREEN:			0xFF00FF00;
			case CYAN:			0xFF00FFFF;
			case RED:			0xFFFF0000;
			case MAGENTA:		0xFFFF00FF;
			case YELLOW:		0xFFFFFF00;
			case WHITE | _:		0xFFFFFFFF;
		}
	}
}

enum abstract FileAttribute(Int) from Int to Int {
	// Settables
	var ARCHIVE = 0x20;
	var HIDDEN = 0x2;
	var NORMAL = 0x80;
	var NOT_CONTENT_INDEXED = 0x2000;
	var OFFLINE = 0x1000;
	var READONLY = 0x1;
	var SYSTEM = 0x4;
	var TEMPORARY = 0x100;

	// Non Settables
	var COMPRESSED = 0x800;
	var DEVICE = 0x40;
	var DIRECTORY = 0x10;
	var ENCRYPTED = 0x4000;
	var REPARSE_POINT = 0x400;
	var SPARSE_FILE = 0x200;
}

enum abstract ConsoleColor(Int) {
	var BLACK = 0;
	var DARKBLUE = 1;
	var DARKGREEN = 2;
	var DARKCYAN = 3;
	var DARKRED = 4;
	var DARKMAGENTA = 5;
	var DARKYELLOW = 6;
	var LIGHTGRAY = 7;
	var GRAY = 8;
	var BLUE = 9;
	var GREEN = 10;
	var CYAN = 11;
	var RED = 12;
	var MAGENTA = 13;
	var YELLOW = 14;
	var WHITE = 15;

	var NONE = -1;
}

enum abstract MessageBoxIcon(Int) {
	var MSG_ERROR = 0x00000010;
	var MSG_QUESTION = 0x00000020;
	var MSG_WARNING = 0x00000030;
	var MSG_INFORMATION = 0x00000040;
}

enum abstract CodeCursor(String) {
	var CUSTOM;// = "arrow";
	var ARROW;// = "arrow";
	var CLICK;// = "click";
	var CROSSHAIR;// = "crosshair";
	var HAND;// = "hand";
	var IBEAM;// = "ibeam";
	var MOVE;// = "move";

	var RESIZE_H;// = "resize_we";
	var RESIZE_V;// = "resize_ns";
	var RESIZE_TL;// = "resize_nw";
	var RESIZE_TR;// = "resize_ne";
	var RESIZE_BL;// = "resize_sw";
	var RESIZE_BR;// = "resize_se";
	var RESIZE_T;// = "resize_n";
	var RESIZE_B;// = "resize_b";
	var RESIZE_L;// = "resize_w";
	var RESIZE_R;// = "resize_e";

	var RESIZE_TLBR;// = "resize_nw_se";
	var RESIZE_TRBL;// = "resize_ne_sw";

	var WAIT;// = "wait";
	var WAIT_ARROW;// = "waitarrow";
	var DISABLED;// = "disabled";
	var DRAG;// = "drag";
	var DRAG_OPEN;// = "dragopen";

	@:to public function toOpenFL():MouseCursor {
		return @:privateAccess switch(cast this) {
			case ARROW: MouseCursor.ARROW;
			case CROSSHAIR: MouseCursor.__CROSSHAIR;
			case CLICK: MouseCursor.BUTTON;
			case IBEAM: MouseCursor.IBEAM;
			case MOVE: MouseCursor.__MOVE;
			case HAND: MouseCursor.HAND;
			case DRAG: MouseCursor.HAND;
			case DRAG_OPEN: MouseCursor.ARROW; // Could be HAND, but it might be better to use ARROW since on windows it would be weird to have the dragging cursor
			case WAIT: MouseCursor.__WAIT;
			case WAIT_ARROW: MouseCursor.__WAIT_ARROW;

			case DISABLED: MouseCursor.ARROW;

			case RESIZE_TR: MouseCursor.__RESIZE_NESW;
			case RESIZE_BL: MouseCursor.__RESIZE_NESW;
			case RESIZE_TL: MouseCursor.__RESIZE_NWSE;
			case RESIZE_BR: MouseCursor.__RESIZE_NWSE;
			case RESIZE_H: MouseCursor.__RESIZE_WE;
			case RESIZE_V: MouseCursor.__RESIZE_NS;

			case RESIZE_T: MouseCursor.__RESIZE_NS;
			case RESIZE_B: MouseCursor.__RESIZE_NS;
			case RESIZE_L: MouseCursor.__RESIZE_WE;
			case RESIZE_R: MouseCursor.__RESIZE_WE;

			case RESIZE_TLBR: MouseCursor.__RESIZE_NWSE;
			case RESIZE_TRBL: MouseCursor.__RESIZE_NESW;
			case CUSTOM: MouseCursor.__CUSTOM;
			//default: ARROW;
		}
	}

	@:to public function toInt():Int {
		return switch(cast this) {
			case ARROW: 0;
			case CROSSHAIR: 1;
			case CLICK: 2;
			case IBEAM: 3;
			case MOVE: 4;
			case HAND: 5;
			case DRAG: 6;
			case DRAG_OPEN: 7;
			case WAIT: 8;
			case WAIT_ARROW: 9;

			case DISABLED: 10;

			case RESIZE_TR: 11;
			case RESIZE_BL: 12;
			case RESIZE_TL: 13;
			case RESIZE_BR: 14;
			case RESIZE_H: 15;
			case RESIZE_V: 16;

			case RESIZE_T: 17;
			case RESIZE_B: 18;
			case RESIZE_L: 19;
			case RESIZE_R: 20;

			case RESIZE_TLBR: 21;
			case RESIZE_TRBL: 22;

			case CUSTOM: -1;
		}
	}
}