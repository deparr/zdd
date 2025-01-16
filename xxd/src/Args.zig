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

format: Format,
autoskip: bool,
columns: usize,
capitalize_name: bool,
uppercase_hex: bool,
encoding: Encoding,
groupsize: usize,
length: ?usize,
name: ?[]const u8,
offset: usize,
offset_fmt: OffsetFmt,
infile: ?[]const u8,
outfile: ?[]const u8,
it: std.process.ArgIterator,

const Format = enum { hex, bin, include, plain, reverse, words };

const Encoding = enum { ascii, ebcdic };

const OffsetFmt = enum { hex, dec };

// todo -r reverse
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

    const process_name = it.next() orelse "xxd";

    var end_of_args = false;

    var format_o: ?Args.Format = null;
    var autoskip: bool = false;
    var columns_o: ?usize = null;
    var capitalize_name: bool = false;
    var uppercase_hex: bool = false;
    var encoding: Args.Encoding = .ascii;
    var groupsize_o: ?usize = null;
    var length: ?usize = null;
    var name: ?[]const u8 = null;
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
                format_o = .bin;
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
                format_o = .words;
            },
            .@"-g", .@"-groupsize" => {
                const group_num = nextArg(&it, "groupsize", process_name);
                const group_p = std.fmt.parseInt(usize, group_num, 10) catch continue;
                groupsize_o = group_p;
            },
            .@"-h", .@"-help" => {
                help(process_name);
            },
            .@"-i", .@"-include" => {
                format_o = .include;
            },
            .@"-l", .@"-len" => {
                const len_num = nextArg(&it, "length", process_name);
                const len_p = std.fmt.parseInt(usize, len_num, 10) catch continue;
                length = len_p;
            },
            .@"-L", .@"-language" => {
            },
            .@"-n", .@"-name" => {
                name = nextArg(&it, "name", process_name);
            },
            .@"-o" => {
                const offset_num = nextArg(&it, "offet", process_name);
                const offset_p = std.fmt.parseInt(usize, offset_num, 10) catch continue;
                offset = offset_p;
            },
            .@"-p", .@"-ps", .@"-postscript", .@"-plain" => {
                format_o = .plain;
            },
            .@"-r" => {
                unreachable;
            },
            .@"-u" => {
                uppercase_hex = true;
            },
            .@"-v", .@"-version" => {
                version();
            },
        }
    }

    const format = format_o orelse .hex;
    const groupsize = groupsize_o orelse defaultGroupsize(format);
    const columns = columns_o orelse defaultColumns(format);

    if (format == .words and @popCount(groupsize) > 1)
        return ParseError.InvalidWordGroupSize;

    if (format != .plain and columns > max_columns)
        return ParseError.TooManyColumns;

    return .{
        .format = format,
        .autoskip = autoskip,
        .columns = columns,
        .capitalize_name = capitalize_name,
        .uppercase_hex = uppercase_hex,
        .encoding = encoding,
        .groupsize = groupsize,
        .length = length,
        .name = name,
        .offset = offset,
        .offset_fmt = offset_fmt,
        .infile = infile,
        .outfile = outfile,
        .it = it,
    };
}

fn nextArg(it: *std.process.ArgIterator, comptime field: []const u8, process_name: []const u8) []const u8 {
    const val = it.next() orelse {
        std.log.err("No " ++ field ++ " provided", .{});
        help(process_name);
    };

    return val;
}

fn defaultColumns(fmt: ?Args.Format) usize {
    const hex_def: usize = 16;
    const bit_def: usize = 6;
    const inc_def: usize = 12;
    const pst_def: usize = 30;

    return if (fmt) |f| switch (f) {
        .hex, .words => hex_def,
        .bin => bit_def,
        .include => inc_def,
        .plain => pst_def,
        .reverse => unreachable,
    } else hex_def;
}

fn defaultGroupsize(fmt: ?Args.Format) usize {
    const hex_def: usize = 2;
    const bit_def: usize = 1;
    const end_def: usize = 4;

    return if (fmt) |f| switch (f) {
        .hex => hex_def,
        .bin => bit_def,
        .words => end_def,
        else => 0,
    } else hex_def;
}

pub fn deinit(self: *Args) void {
    self.it.deinit();
}

pub fn dump(self: *Args) void {
    std.debug.print(
        \\Args{{
        \\  command: {s}
        \\  autoskip: {}
        \\  columns: {d}
        \\  capitalize_name: {}
        \\  uppercase_hex: {}
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
        @tagName(self.format),
        self.autoskip,
        self.columns,
        self.capitalize_name,
        self.uppercase_hex,
        @tagName(self.encoding),
        self.groupsize,
        self.length,
        self.offset,
        @tagName(self.offset_fmt),
        self.infile,
        self.outfile,
    });

}
