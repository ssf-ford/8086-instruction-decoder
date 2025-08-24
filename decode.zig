const std = @import("std");
// 8086/8088 Instruction Format
// 765432 10 | 76  543 210 | Byte3 Byte4
// Opcode DW | MOD REG R/M |

const MOV: u8 = 0x88; // 1000 1000
const D_BIT: u8 = 0x02; // 0000 0010
const W_BIT: u8 = 0x01;
const REG: u8 = 0b000000111000;
const RM: u8 = 0b000000000111;
const Instruction = struct { op: []const u8, direction: bool, wide: bool };
const Register = struct { dest: []const u8, src: []const u8 };

const DecodeError = error{
    InvalidOp,
    InvalidReg,
};

fn decode_instruction(b: u8) DecodeError!Instruction {
    var op: []const u8 = "";
    const d: bool = (b & D_BIT > 0);
    const w: bool = (b & W_BIT > 0);

    // Create a lookup table here for additional operations
    if (b & MOV > 0) {
        op = "mov";
    } else {
        return DecodeError.InvalidOp;
    }

    return Instruction{ .op = op, .direction = d, .wide = w };
}

fn get_reg_name(b: u8, w: bool) DecodeError![]const u8 {
    var reg_name: []const u8 = "";
    switch (w) {
        true => reg_name = switch (b) {
            0 => "ax",
            1 => "cx",
            2 => "dx",
            3 => "bx",
            4 => "sp",
            5 => "bp",
            6 => "si",
            7 => "di",
            else => {
                return DecodeError.InvalidReg;
            },
        },
        false => reg_name = switch (b) {
            0 => "al",
            1 => "cl",
            2 => "dl",
            3 => "bl",
            4 => "ah",
            5 => "ch",
            6 => "dh",
            7 => "bh",
            else => {
                return DecodeError.InvalidReg;
            },
        },
    }

    return reg_name;
}

fn decode_register(b: u8, instruction: *Instruction) DecodeError!Register {
    var dest: []const u8 = "";
    var src: []const u8 = "";

    switch (instruction.*.direction) {
        true => {
            src = try get_reg_name(b & RM, instruction.*.wide);
            dest = try get_reg_name((b & REG) >> 3, instruction.*.wide);
        },
        false => {
            src = try get_reg_name((b & REG) >> 3, instruction.*.wide);
            dest = try get_reg_name(b & RM, instruction.*.wide);
        },
    }

    return Register{ .src = src, .dest = dest };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <filename>\n", .{args[0]});
        return;
    }

    const filename = args[1];
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ filename, err });
        return;
    };
    defer file.close();

    var buffer: [1024]u8 = undefined;
    const bytes_read = file.readAll(buffer[0..]) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };

    if (bytes_read < 2) {
        std.debug.print("File must contain at least 2 bytes\n", .{});
        return;
    }

    std.debug.print("bit 16\n\n", .{});
    var i: usize = 0;
    while (i + 1 < bytes_read) {
        var instruction = decode_instruction(buffer[i]) catch |err| {
            std.debug.print("Error decoding instruction at byte {}: {}\n", .{ i, err });
            i += 1;
            continue;
        };

        const register = decode_register(buffer[i + 1], &instruction) catch |err| {
            std.debug.print("Error decoding register at byte {}: {}\n", .{ i + 1, err });
            i += 1;
            continue;
        };

        std.debug.print("{s} {s}, {s}\n", .{ instruction.op, register.dest, register.src });
        i += 2;
    }
}
