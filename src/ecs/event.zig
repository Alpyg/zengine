const std = @import("std");

const zflecs = @import("zflecs");

const z = @import("../root.zig");
const Ecs = z.Ecs;

pub fn Event(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const EVENT_QUEUE = {};

        pub const Queue = std.DoublyLinkedList(T);

        writer: WriterImpl = undefined,
        reader: ReaderImpl = undefined,

        pub fn init(_: *Ecs) Self {
            const queue = z.allocator.create(Queue) catch @panic("OOM");
            queue.* = .{};

            return Self{
                .writer = .{ .queue = queue, .arena = std.heap.ArenaAllocator.init(z.allocator) },
                .reader = .{ .queue = queue },
            };
        }

        pub const Writer = struct {
            impl: *WriterImpl,

            pub inline fn init(world: *zflecs.world_t) Writer {
                return Writer{ .impl = &zflecs.singleton_get_mut(world, Self).?.writer };
            }

            pub fn send(self: Writer, value: T) !void {
                try self.impl.send(value);
            }

            pub fn clear(self: Writer) void {
                self.impl.clear();
            }
        };

        pub const WriterImpl = struct {
            queue: *Queue,
            arena: std.heap.ArenaAllocator,

            pub inline fn init(world: *zflecs.world_t) WriterImpl {
                return zflecs.singleton_get_mut(world, Self).?.writer;
            }

            pub inline fn send(self: *WriterImpl, value: T) !void {
                var allocator = self.arena.allocator();
                const node = try allocator.create(Queue.Node);
                node.*.data = value;
                self.queue.append(node);
            }

            pub inline fn clear(self: *WriterImpl) void {
                _ = self.arena.reset(.free_all);
                self.queue.* = .{};
            }
        };

        pub const Reader = struct {
            impl: *ReaderImpl,

            pub inline fn init(world: *zflecs.world_t) Reader {
                return Reader{ .impl = &zflecs.singleton_get_mut(world, Self).?.reader };
            }

            pub fn read(self: Reader) ?T {
                return self.impl.read();
            }
        };

        pub const ReaderImpl = struct {
            queue: *Queue,
            node: ?*Queue.Node = null,

            pub inline fn read(self: *ReaderImpl) ?T {
                self.node = if (self.node == null)
                    self.queue.first
                else
                    self.node.?.next;

                if (self.node) |node| {
                    return node.data;
                }
                return null;
            }
        };

        pub const EventClearSystem = z.System(struct {
            pub const phase = &z.Pipeline.Last;

            pub fn run(event: z.Event(T).Writer) void {
                event.clear();
            }
        });
    };
}
