const std = @import("std");

const KeyState = packed struct {
    keys: u32 = 0, // 256 bits (32 bytes)

    fn setBit(value: *u32, index: u5, is_set: bool) void {
        if (is_set) {
            value.* |= @as(u32, 1) << index; // Set bit
        } else {
            value.* &= ~(@as(u32, 1) << index); // Clear bit
        }
    }

    fn getBit(value: u32, index: u5) bool {
        return (value & (@as(u32, 1) << index)) != 0;
    }

    /// **Set a key state (press or release)**
    pub fn setKey(self: *KeyState, keycode: u5, is_pressed: bool) void {
        setBit(&self.keys, keycode, is_pressed);
    }

    /// **Check if a key is currently pressed**
    pub fn isKeyPressed(self: *const KeyState, keycode: u5) bool {
        return getBit(self.keys, keycode);
    }

    /// **Clear all key states (reset)**
    pub fn clear(self: *KeyState) void {
        @memset(&self.keys, 0);
    }
};

pub fn main() void {
    var keyboard = KeyState{};

    std.debug.print("size of keys array {} bytes\n", .{@sizeOf(KeyState)});

    // Press keys (example: 'A' = 65, 'Space' = 32)
    keyboard.setKey(1, true); // Press 'A'
    keyboard.setKey(2, true); // Press 'Space'

    // Check key states
    std.debug.print("Is 'A' pressed? {}\n", .{keyboard.isKeyPressed(1)});
    std.debug.print("Is 'Space' pressed? {}\n", .{keyboard.isKeyPressed(2)});
    std.debug.print("Is 'B' pressed? {}\n", .{keyboard.isKeyPressed(3)});

    // Release 'A'
}
