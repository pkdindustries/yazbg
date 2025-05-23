// engine/events.zig - Generic event queue system
const std = @import("std");

// ---------------------------------------------------------------------------
// Event Queue System
// ---------------------------------------------------------------------------

pub fn EventQueue(comptime EventType: type) type {
    return struct {
        const Self = @This();
        
        pub const Record = struct {
            event: EventType,
            timestamp: i64,
            source: Source = .Game,
        };

        pub const Source = enum {
            Input,
            Game,
            System,
        };

        events: std.ArrayList(Record),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .events = std.ArrayList(Record).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.events.deinit();
        }

        pub fn push(self: *Self, event: EventType, source: Source) !void {
            try self.events.append(.{
                .event = event,
                .timestamp = std.time.milliTimestamp(),
                .source = source,
            });
        }

        pub fn pushSimple(self: *Self, event: EventType) !void {
            try self.push(event, .Game);
        }

        pub fn clear(self: *Self) void {
            self.events.clearRetainingCapacity();
        }

        pub fn items(self: *const Self) []const Record {
            return self.events.items;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.events.items.len == 0;
        }

        // Process a batch of input key mappings
        pub fn processInputMappings(
            self: *Self,
            comptime mappings: anytype,
            isKeyPressed: *const fn (key: c_int) bool,
        ) !void {
            inline for (mappings) |mapping| {
                if (isKeyPressed(mapping[0])) {
                    try self.push(mapping[1], .Input);
                }
            }
        }
    };
}

// ---------------------------------------------------------------------------
// Global Event System Manager (optional convenience)
// ---------------------------------------------------------------------------

pub fn EventSystem(comptime EventType: type) type {
    return struct {
        const Queue = EventQueue(EventType);
        
        var instance: ?Queue = null;
        
        pub fn init(allocator: std.mem.Allocator) void {
            instance = Queue.init(allocator);
        }
        
        pub fn deinit() void {
            if (instance) |*q| {
                q.deinit();
                instance = null;
            }
        }
        
        pub fn queue() *Queue {
            return &instance.?;
        }
        
        pub fn push(event: EventType, source: Queue.Source) void {
            instance.?.push(event, source) catch |err| {
                std.debug.print("Failed to push event: {}\n", .{err});
            };
        }
        
        pub fn clear() void {
            instance.?.clear();
        }
        
        pub fn items() []const Queue.Record {
            return instance.?.items();
        }
    };
}