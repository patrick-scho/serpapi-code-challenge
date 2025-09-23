const std = @import("std");

/// find the next occurence of 'c' that is not within "quotes"
fn next_not_in_str(str: []const u8, index: usize, c: u8) ?usize {
    var in_str: bool = false;

    for (index..str.len) |i| {
        if (!in_str) {
            if (str[i] == '"') {
                in_str = true;
            } else if (str[i] == c) {
                return i;
            }
        } else {
            // if we encounter a ", and the last character was not a \
            // the string is closed
            if (str[i] == '"' and i > index and str[i - 1] != '\\') {
                in_str = false;
            }
        }
    }

    return null;
}

/// find the next tag enclosed in <>
fn next_tag(str: []const u8, index: *usize) ?[]const u8 {
    while (index.* < str.len) {
        const a = next_not_in_str(str, index.*, '<') orelse return null;
        const b = next_not_in_str(str, a + 1, '>') orelse return null;
        // try to find a space to delimit tag name
        const c = std.mem.indexOfScalarPos(u8, str, a, ' ') orelse b;
        index.* = b + 1;
        // if the tag is immediately closed <tag>, the next space
        // will not be part of the tag name, hence the @min
        return str[a + 1 .. @min(b, c)];
    }
    return null;
}

/// match the given html string to the nested Tag
fn match(str: []const u8, tag: Tag) !void {
    var index: usize = 0;
    _ = tag;

    while (next_tag(str, &index)) |t| {
        // if we encounter a script tag, we skip it to avoid
        // parsing javascript and hope that there is no
        // </script> inside any strings in the js
        if (std.mem.eql(u8, t, "script")) {
            index = std.mem.indexOfPos(u8, str, index, "</script>") orelse return error.ScriptNotClosed;
        }
        // print all tags for now
        std.debug.print("<{s}>\n", .{t});
    }
}

/// simple Tag struct to represent the structure we are looking for
const Tag = struct {
    name: []const u8,
    children: ?[]const Tag = null,
};

pub fn main() !void {
    // create allocator for reading file
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    // read file
    const f = try std.fs.cwd().openFile("files/van-gogh-paintings.html", .{});
    const s = try f.readToEndAlloc(alloc, 1024 * 1024 * 1024);
    f.close();

    // specify the tag structure we are looking for
    const t: Tag =
        .{ .name = "div", .children = &.{
            .{ .name = "a", .children = &.{
                .{ .name = "img" },
                .{ .name = "div", .children = &.{
                    .{ .name = "div" },
                    .{ .name = "div" },
                } },
            } },
        } };

    // look for match
    try match(s, t);
}
