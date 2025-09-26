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
    
    /// get a named attribute from the attribute section extracted from a tag
    fn get_attr(self: ParsedTag, attr: []const u8) ?[]const u8 {
        if (self.attrs == null) return null;
        const attr_start = std.mem.indexOf(u8, self.attrs.?, attr) orelse return null;
        return next_str(self.attrs.?[attr_start..self.attrs.?.len]);
    }
};

/// struct that contains a tag pair and content
const ParsedTagPair = struct {
    tag: ParsedTag,
    content: []const u8,
};

/// find the next tag enclosed in <>
fn next_tag(str: []const u8, index: *usize) ?ParsedTag {
    while (index.* < str.len) {
        // find start and end <>
        const start = next_not_in_str(str, index.*, '<') orelse return null;
        const end = next_not_in_str(str, start + 1, '>') orelse return null;
        // check if there is a space inside the tag (there are attributes)
        var has_space = std.mem.indexOfScalarPos(u8, str, start, ' ');
        if (has_space != null and has_space.? >= end) has_space = null;
        index.* = end + 1;

        // create result depending on if there is a space or not
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

/// get tag pair <tag></tag> including the inner content
fn next_tag_pair(str: []const u8, index: *usize) ?ParsedTagPair {
    const tag = next_tag(str, index) orelse return null;
    const content_start = index.*;
    const content_end = std.mem.indexOfScalarPos(u8, str, content_start, '<') orelse return null;
    _ = next_tag(str, index);
    return .{
        .tag = tag,
        .content = str[content_start..content_end],
    };
}

/// match a tag name, checking for a starting /
fn match_tag_name(tag: []const u8, name: []const u8) bool {
    const start: usize = if (tag[0] == '/') 1 else 0;
    return std.mem.eql(u8, tag[start..tag.len], name);
}

/// try matching exactly one tag
fn match_one(str: []const u8, index: *usize, tag: Tag) ?[]const u8 {
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
            _ = match_one(str, index, child) orelse return null;
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
        if (match_one(str, &try_index, tag)) |result| {
            return result;
        }
    }
    return null;
}

/// simple Tag struct to represent the structure we are looking for
const Tag = struct {
    name: []const u8,
    children: []const Tag = &.{},
    end_tag: bool = true,
};

/// target Artwork structure
const Artwork = struct {
    name: []const u8,
    extensions: [1][]const u8,
    link: []const u8,
    image: []const u8,

    /// print a result as a json object
    fn print_json(self: Artwork, writer: anytype) !void {
        try writer.print("    {{\n", .{});
        try writer.print("      \"name\": \"{s}\",\n", .{self.name});
        try writer.print("      \"extensions\": [ \"{s}\" ],\n", .{self.extensions[0]});
        try writer.print("      \"link\": \"https://www.google.com{s}\",\n", .{self.link});
        try writer.print("      \"image\": \"{s}\",\n", .{self.image});
        try writer.print("    }},\n", .{});
    }

    /// parse relevant info from string containing
    /// the previously searched pattern
    fn parse(str: []const u8) Artwork {
        var index: usize = 0;

        // we know the tags are there so we can
        // immediately unwrap with .?
        _ = next_tag(str, &index); // skip unneeded div
        const a = next_tag(str, &index).?;
        const img = next_tag(str, &index).?;
        _ = next_tag(str, &index); // skip again
        const div1 = next_tag_pair(str, &index).?;
        const div2 = next_tag_pair(str, &index).?;

        return .{
            .name = div1.content,
            .extensions = .{div2.content},
            .link = a.get_attr("href") orelse "",
            .image = img.get_attr("src") orelse "",
        };
    }
};

// tests and main

/// helper function to read a file
fn read_file(alloc: std.mem.Allocator, filename: []const u8) ![]const u8 {
    // read file
    const f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();
    return try f.readToEndAlloc(alloc, 1024 * 1024 * 1024);
}

pub fn main() !void {
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator.deinit();
    const alloc = allocator.allocator();

    const s = try read_file(alloc, "files/van-gogh-paintings.html");
    defer alloc.free(s);
    
    var artworks = try test_process_file(alloc, s);
    defer artworks.deinit(alloc);
    
    try test_print_json(artworks.items);
}

fn test_process_file(alloc: std.mem.Allocator, str: []const u8) !std.ArrayList(Artwork) {
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
    
    // collect matches
    var artworks = try std.ArrayList(Artwork).initCapacity(alloc, 10);

    var index: usize = 0;
    while (match(str, &index, t)) |hit| {
        // parse Artwork from string
        const artwork = Artwork.parse(hit);
        try artworks.append(alloc, artwork);
    }

    return artworks;
}

fn test_print_json(artworks: []const Artwork) !void {
    // get a handle to stdout
    const out = std.fs.File.stdout();
    var writer = out.deprecatedWriter();

    // start printing json
    try writer.print("{{\n  \"artworks\": [\n", .{});

    // output json objects
    for (artworks) |artwork| {
        try artwork.print_json(writer);
    }

    // finish json
    try writer.print("  ]\n}}\n", .{});
}

test "van-gogh-json" {
    const alloc = std.testing.allocator;

    const s = try read_file(alloc, "files/van-gogh-paintings.html");
    defer alloc.free(s);
    
    var artworks = try test_process_file(alloc, s);
    defer artworks.deinit(alloc);
    
    try test_print_json(artworks.items);
}

test "claude-monet-json" {
    const alloc = std.testing.allocator;

    const s = try read_file(alloc, "files/claude-monet-paintings.html");
    defer alloc.free(s);
    
    var artworks = try test_process_file(alloc, s);
    defer artworks.deinit(alloc);
    
    try test_print_json(artworks.items);
}
test "pablo-picasso-json" {
    const alloc = std.testing.allocator;

    const s = try read_file(alloc, "files/pablo-picasso-paintings.html");
    defer alloc.free(s);
    
    var artworks = try test_process_file(alloc, s);
    defer artworks.deinit(alloc);
    
    try test_print_json(artworks.items);
}

test "van-gogh-entries" {
    const alloc = std.testing.allocator;

    const s = try read_file(alloc, "files/van-gogh-paintings.html");
    defer alloc.free(s);
    
    var artworks = try test_process_file(alloc, s);
    defer artworks.deinit(alloc);
    
    std.debug.assert(std.mem.eql(u8, artworks.items[0].name, "The Starry Night"));
    std.debug.assert(std.mem.eql(u8, artworks.items[1].name, "Van Gogh self-portrait"));
    std.debug.assert(std.mem.eql(u8, artworks.items[2].name, "The Potato Eaters"));
    std.debug.assert(std.mem.eql(u8, artworks.items[3].name, "Wheatfield with Crows"));
    std.debug.assert(std.mem.eql(u8, artworks.items[4].name, "Café Terrace at Night"));
    std.debug.assert(std.mem.eql(u8, artworks.items[5].name, "Almond Blossoms"));
    std.debug.assert(std.mem.eql(u8, artworks.items[6].name, "Vase with Fifteen Sunflowers"));
    std.debug.assert(std.mem.eql(u8, artworks.items[7].name, "Self-Portrait"));

    std.debug.assert(std.mem.eql(u8, artworks.items[0].extensions[0], "1889"));
    std.debug.assert(std.mem.eql(u8, artworks.items[1].extensions[0], "1889"));
    std.debug.assert(std.mem.eql(u8, artworks.items[2].extensions[0], "1885"));
    std.debug.assert(std.mem.eql(u8, artworks.items[3].extensions[0], "1890"));
    std.debug.assert(std.mem.eql(u8, artworks.items[4].extensions[0], "1888"));
    std.debug.assert(std.mem.eql(u8, artworks.items[5].extensions[0], "1890"));
    std.debug.assert(std.mem.eql(u8, artworks.items[6].extensions[0], "1888"));
    std.debug.assert(std.mem.eql(u8, artworks.items[7].extensions[0], "1889"));
}

