const std = @import("std");
const Allocator = std.mem.Allocator;

const version_str = "stupidxxd-0.0.0";

pub fn help(process_name: []const u8) noreturn {
    std.debug.print(
        \\Usage:
        \\       {s} [options] [infile [outfile]]
        \\    or
        \\       {s} -r [-s [-]offset] [-c cols] [-ps] [infile [outfile]]
        \\Options:
        \\    -a          toggle autoskip: A single '*' replaces nul-lines. Default off.
        \\    -b          binary digit dump (incompatible with -ps,-i,-r). Default hex.
        \\    -C          capitalize variable names in C include file style (-i).
        \\    -c cols     format <cols> octets per line. Default 16 (-i: 12, -ps: 30).
        \\    -E          show characters in EBCDIC. Default ASCII.
        \\    -e          little-endian dump (incompatible with -ps,-i,-r).
        \\    -g bytes    number of octets per group in normal output. Default 2 (-e: 4).
        \\    -h          print this summary.
        \\    -i          output in C include file style.
        \\    -l len      stop after <len> octets.
        \\    -n name     set the variable name used in C include output (-i).
        \\    -o off      add <off> to the displayed file position.
        \\    -ps         output in postscript plain hexdump style.
        \\    -r          reverse operation: convert (or patch) hexdump into binary.
        \\    -r -s off   revert with <off> added to file positions found in hexdump.
        \\    -d          show offset in decimal instead of hex.
        \\    -s [+][-]seek  start at <seek> bytes abs. (or +: rel.) infile offset.
        \\    -u          use upper case hex letters.
        \\    -v          show version: "{s}".
    , .{ process_name, process_name, version_str });
    std.process.exit(1);
}

fn version() noreturn {
    std.debug.print("{s}\n", .{version_str});
    std.process.exit(0);
}

const Args = @This();

command: Command,
format: Format,
autoskip: bool,
columns: usize,
capitalize_name: bool,
encoding: Encoding,
groupsize: usize,
length: ?usize,
name: ?[]u8,
language: Language,
offset: usize,
offset_fmt: OffsetFmt,
infile: ?[]const u8,
outfile: ?[]const u8,
it: std.process.ArgIterator,
alloc: Allocator,

const Command = enum { grouped, include, plain, patch, words };
const Format = enum { hex, bin, hex_upper };
const Encoding = enum { ascii, ebcdic };
const OffsetFmt = enum { hex, dec, none };
const Language = enum { c, zig };

const Switch = enum {
    @"-a",
    @"-autoskip",
    @"-b",
    @"-bits",
    @"-c",
    @"-cols",
    @"-C",
    @"-d",
    @"-capitalize",
    @"-E",
    @"-EBCDIC",
    @"-e",
    @"-g",
    @"-groupsize",
    @"-h",
    @"-help",
    @"-i",
    @"-include",
    @"-l",
    @"-len",
    @"-L",
    @"-language",
    @"-n",
    @"-name",
    @"-o",
    @"-p",
    @"-ps",
    @"-postscript",
    @"-plain",
    @"-r",
    @"-u",
    @"-v",
    @"-version",
};

pub const ParseError = error{
    TooManyColumns,
    InvalidWordGroupSize,
    OutOfMemory,
};

pub fn parse(alloc: Allocator) Args.ParseError!Args {
    const max_columns: usize = 256;
    var it = try std.process.argsWithAllocator(alloc);

    const process_name = it.next() orelse "zdd";

    var end_of_args = false;

    var command: Args.Command = .grouped;
    var format: Args.Format = .hex;
    var autoskip: bool = false;
    var columns_o: ?usize = null;
    var capitalize_name: bool = false;
    var encoding: Args.Encoding = .ascii;
    var groupsize_o: ?usize = null;
    var length: ?usize = null;
    var name_o: ?[]const u8 = null;
    var language: Args.Language = .c;
    var offset: usize = 0;
    var offset_fmt: Args.OffsetFmt = .hex;
    var infile: ?[]const u8 = null;
    var outfile: ?[]const u8 = null;

    while (it.next()) |arg| {
        if (!end_of_args and std.mem.eql(u8, arg, "--")) {
            end_of_args = true;
            continue;
        }

        if (end_of_args) {
            if (infile) |_| {
                outfile = arg;
            } else infile = arg;

            continue;
        }

        const parsed = (std.meta.stringToEnum(Switch, arg)) orelse {
            end_of_args = true;
            infile = arg;
            continue;
        };

        switch (parsed) {
            .@"-a", .@"-autoskip" => {
                autoskip = true;
            },
            .@"-b", .@"-bits" => {
                format = .bin;
            },
            .@"-c", .@"-cols" => {
                const cols = nextArg(&it, "columns", process_name);
                const cols_num = std.fmt.parseInt(u9, cols, 10) catch continue;
                columns_o = cols_num;
            },
            .@"-C", .@"-capitalize" => {
                capitalize_name = true;
            },
            .@"-d" => {
                offset_fmt = .dec;
            },
            .@"-E", .@"-EBCDIC" => {
                encoding = .ebcdic;
            },
            .@"-e" => {
                command = .words;
            },
            .@"-g", .@"-groupsize" => {
                const group_num = nextArg(&it, "groupsize", process_name);
                groupsize_o = std.fmt.parseInt(usize, group_num, 10) catch continue;
            },
            .@"-h", .@"-help" => {
                help(process_name);
            },
            .@"-i", .@"-include" => {
                command = .include;
                offset_fmt = .none;
            },
            .@"-l", .@"-len" => {
                const len_num = nextArg(&it, "length", process_name);
                length = std.fmt.parseInt(usize, len_num, 10) catch continue;
            },
            .@"-L", .@"-language" => {
                const given = nextArg(&it, "language", process_name);
                language = std.meta.stringToEnum(Args.Language, given) orelse .c;
            },
            .@"-n", .@"-name" => {
                name_o = nextArg(&it, "name", process_name);
            },
            .@"-o" => {
                const offset_num = nextArg(&it, "offet", process_name);
                offset = std.fmt.parseInt(usize, offset_num, 10) catch continue;
            },
            .@"-p", .@"-ps", .@"-postscript", .@"-plain" => {
                command = .plain;
                offset_fmt = .none;
            },
            .@"-r" => {
                command = .patch;
            },
            .@"-u" => {
                if (format == .hex) format = .hex_upper;
            },
            .@"-v", .@"-version" => {
                version();
            },
        }
    }

    const groupsize = groupsize_o orelse defaultGroupsize(command, format);
    const columns = columns_o orelse defaultColumns(command, format);

    if (command == .words and @popCount(groupsize) > 1)
        return ParseError.InvalidWordGroupSize;

    if (command != .plain and columns > max_columns)
        return ParseError.TooManyColumns;

    const passed_name = name_o orelse if (infile) |path| std.fs.path.basename(path) else null;
    var name: ?[]u8 = null;
    if (passed_name) |n|
        name = try makeName(n, capitalize_name, alloc);

    return .{
        .command = command,
        .format = format,
        .autoskip = autoskip,
        .columns = columns,
        .capitalize_name = capitalize_name,
        .encoding = encoding,
        .groupsize = groupsize,
        .length = length,
        .name = name,
        .language = language,
        .offset = offset,
        .offset_fmt = offset_fmt,
        .infile = infile,
        .outfile = outfile,
        .it = it,
        .alloc = alloc,
    };
}

fn nextArg(it: *std.process.ArgIterator, comptime field: []const u8, process_name: []const u8) []const u8 {
    const val = it.next() orelse {
        std.log.err("No " ++ field ++ " provided", .{});
        help(process_name);
    };

    return val;
}

fn makeName(passed: []const u8, capitalize: bool, alloc: Allocator) ![]u8 {
    std.debug.assert(passed.len > 0);
    var len = passed.len;
    var start: usize = 0;
    if (std.ascii.isDigit(passed[0])) {
        len += 2;
        start = 2;
    }
    var name_cpy = try alloc.alloc(u8, len);

    if (std.ascii.isDigit(passed[0])) {
        name_cpy[0] = '_';
        name_cpy[1] = '_';
    }

    @memcpy(name_cpy[start..], passed);

    for (0..name_cpy.len) |i| {
        switch (name_cpy[i]) {
            '_', 'A'...'Z', '0'...'9' => {},
            'a'...'z' => if (capitalize) {
                name_cpy[i] = name_cpy[i] + 0x20;
            },
            else => name_cpy[i] = '_',
        }
    }

    return name_cpy;
}

fn defaultColumns(cmd: Args.Command, fmt: Args.Format) usize {
    const hex_def: usize = 16;
    const bit_def: usize = 6;
    const inc_def: usize = 12;
    const pst_def: usize = 30;

    return switch (cmd) {
        .grouped => switch (fmt) {
            .hex, .hex_upper => hex_def,
            .bin => bit_def,
        },
        .include => inc_def,
        .words => hex_def,
        .plain => pst_def,
        else => 0,
    };
}

fn defaultGroupsize(cmd: Args.Command, fmt: Args.Format) usize {
    const hex_def: usize = 2;
    const bit_def: usize = 1;
    const end_def: usize = 4;

    return switch (cmd) {
        .grouped => switch (fmt) {
            .hex, .hex_upper => hex_def,
            .bin => bit_def,
        },
        .words => switch (fmt) {
            .hex, .hex_upper => end_def,
            .bin => bit_def,
        },
        else => 0,
    };
}

pub fn deinit(self: *Args) void {
    self.it.deinit();
    if (self.name) |name| {
        self.alloc.free(name);
    }
}

pub fn dump(self: *Args) void {
    std.debug.print(
        \\Args{{
        \\  command: {s}
        \\  format: {s}
        \\  autoskip: {}
        \\  columns: {d}
        \\  capitalize_name: {}
        \\  encoding: {s}
        \\  groupsize: {d}
        \\  length: {?}
        \\  offset: {d}
        \\  offset_fmt: {s}
        \\  infile: {?s}
        \\  outfile: {?s}
        \\}}
        \\
    , .{
        @tagName(self.command),
        @tagName(self.format),
        self.autoskip,
        self.columns,
        self.capitalize_name,
        @tagName(self.encoding),
        self.groupsize,
        self.length,
        self.offset,
        @tagName(self.offset_fmt),
        self.infile,
        self.outfile,
    });
}
