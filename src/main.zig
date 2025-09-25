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

/// find the next string enclosed with ""
/// returns the string without quotes
fn next_str(str: []const u8) ?[]const u8 {
    var from: usize = 0;
    var to: usize = 0;

    for (0..str.len) |i| {
        if (str[i] == '"' and i < str.len - 1) {
            from = i + 1;
            break;
        }
    }
    for (from..str.len) |i| {
        // if we encounter a ", and the last character was not a \
        // the string is closed
        if (str[i] == '"' and i > 0 and str[i - 1] != '\\') {
            to = i - 1;
            return str[from..to];
        }
    }

    return null;
}

/// struct that contains the name and attr slices
/// used as return value from next_tag
const ParsedTag = struct {
    name: []const u8,
    attrs: ?[]const u8 = null,
    all: []const u8,
};

/// find the next tag enclosed in <>
fn next_tag(str: []const u8, index: *usize) ?ParsedTag {
    while (index.* < str.len) {
        const start = next_not_in_str(str, index.*, '<') orelse return null;
        const end = next_not_in_str(str, start + 1, '>') orelse return null;
        var has_space = std.mem.indexOfScalarPos(u8, str, start, ' ');
        if (has_space != null and has_space.? >= end) has_space = null;
        index.* = end + 1;

        const result =
            if (has_space) |space|
                ParsedTag{ .name = str[start + 1 .. space], .attrs = str[space + 1 .. end], .all = str[start + 1 .. end] }
            else
                ParsedTag{ .name = str[start + 1 .. end], .all = str[start + 1 .. end] };

        // if we encounter a script tag, we skip it to avoid
        // parsing javascript and hope that there is no
        // </script> inside any strings in the js
        if (std.mem.startsWith(u8, result.name, "script")) {
            index.* = std.mem.indexOfPos(u8, str, index.*, "</script>") orelse return null;
        }

        return result;
    }
    return null;
}

/// match a tag name, checking for a starting /
fn match_tag_name(tag: []const u8, name: []const u8) bool {
    const start: usize = if (tag[0] == '/') 1 else 0;
    return std.mem.eql(u8, tag[start..tag.len], name);
}

/// try matching exactly one tag
fn try_match(str: []const u8, index: *usize, tag: Tag) ?[]const u8 {
    const t = next_tag(str, index) orelse return null;

    // calculate offset of the found tag from str
    const offset = @intFromPtr(t.name.ptr) - @intFromPtr(str.ptr);

    // if it matches our tag
    if (match_tag_name(t.name, tag.name)) {
        // and it has no end tag, success
        if (!tag.end_tag) {
            return str[offset - 1 .. index.*];
        }

        // otherwise check children recursively
        for (tag.children) |child| {
            _ = try_match(str, index, child) orelse return null;
        }

        // and check end tag
        const end_tag = next_tag(str, index) orelse return null;
        if (match_tag_name(end_tag.name, tag.name)) {
            return str[offset - 1 .. index.*];
        }
    }

    return null;
}

/// match the given html string to the nested Tag
/// this function calls try_match for every single tag
/// it doesn't return on failure, but instead keeps going
/// until it finds a match or the string is finished
fn match(str: []const u8, index: *usize, tag: Tag) ?[]const u8 {
    while (index.* < str.len) {
        // remember the index
        var try_index = index.*;
        // call next_tag to advance the index to the next tag
        // since we only want to move the index we can discard the result
        _ = next_tag(str, index) orelse return null;
        // try matching out pattern starting from this tag
        if (try_match(str, &try_index, tag)) |result| {
            return result;
        }
    }
    return null;
}

// TODO: improve
fn get_content(start: []const u8, end: []const u8, str: []const u8) []const u8 {
    const from = @intFromPtr(start.ptr) - @intFromPtr(str.ptr) + start.len;
    const len = @intFromPtr(end.ptr) - @intFromPtr(start.ptr) - start.len;

    return str[from + 1 .. from + len - 1];
}

/// get a named attribute from the attribute section extracted from a tag
fn get_attr(str: ?[]const u8, attr: []const u8) ?[]const u8 {
    if (str == null) return null;
    const attr_start = std.mem.indexOf(u8, str.?, attr) orelse return null;
    return next_str(str.?[attr_start..str.?.len]);
}

/// print a result as a json object
fn print_json(writer: anytype, hit: []const u8) !void {
    const artwork = Artwork.parse(hit);
    try writer.print("    {{\n", .{});
    try writer.print("      \"name\": \"{s}\",\n", .{ artwork.name });
    try writer.print("      \"extensions\": [ \"{s}\" ],\n", .{ artwork.extensions[0] });
    try writer.print("      \"link\": \"https://www.google.com{s}\",\n", .{ artwork.link });
    try writer.print("      \"image\": \"{s}\",\n", .{ artwork.image });
    try writer.print("    }},\n", .{});
}

/// helper function to read a file
fn read_file(alloc: std.mem.Allocator, filename: []const u8) ![]const u8 {
    // read file
    const f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1024 * 1024 * 1024);
}

/// simple Tag struct to represent the structure we are looking for
const Tag = struct {
    name: []const u8,
    children: []const Tag = &.{},
    end_tag: bool = true,
};

const Artwork = struct {
    name: []const u8,
    extensions: [1][]const u8,
    link: []const u8,
    image: []const u8,

    /// parse relevant info from string containing
    /// the previously searched pattern
    fn parse(str: []const u8) Artwork {
        var index: usize = 0;
        _ = next_tag(str, &index).?;
        const a = next_tag(str, &index).?;
        const img = next_tag(str, &index).?;
        _ = next_tag(str, &index).?;
        const div3_start = next_tag(str, &index).?;
        const div3_end = next_tag(str, &index).?;
        const div4_start = next_tag(str, &index).?;
        const div4_end = next_tag(str, &index).?;
        return .{
            .name = get_content(div3_start.all, div3_end.all, str),
            .extensions = [1][]const u8{get_content(div4_start.all, div4_end.all, str)},
            .link = get_attr(a.attrs, "href") orelse "",
            .image = get_attr(img.attrs, "src") orelse "",
        };
    }
};

pub fn main() !void {
    // create allocator for reading file
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // read the file
    // const s = try read_file(alloc, "files/van-gogh-paintings.html");
    // const s = try read_file(alloc, "files/claude-monet-paintings.html");
    const s = try read_file(alloc, "files/pablo-picasso-paintings.html");

    // specify the tag structure we are looking for
    const t: Tag =
        .{ .name = "div", .children = &.{
            .{ .name = "a", .children = &.{
                .{ .name = "img", .end_tag = false },
                .{ .name = "div", .children = &.{
                    .{ .name = "div" },
                    .{ .name = "div" },
                } },
            } },
        } };

    const out = std.fs.File.stdout();
    var writer = out.deprecatedWriter();
    try writer.print("{{\n  \"artworks\": [\n", .{});
    // collect matches
    var index: usize = 0;
    while (match(s, &index, t)) |hit| {
        try print_json(writer, hit);
    }
    try writer.print("  ]\n}}\n", .{});
}
