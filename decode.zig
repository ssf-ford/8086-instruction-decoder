const std = @import("std");
// 8086/8088 Instruction Format
// 765432 10 | 76  543 210 | Byte3 Byte4
// Opcode DW | MOD REG R/M |

const MOV: u8 = 0x88; // 1000 1000
const D_BIT: u8 = 0x02; // 0000 0010
const W_BIT: u8 = 0x01;
const REG: u8 = 0b000000111000;
const RM: u8 = 0b000000000111;
const SR: u8 = 0b00011000; // Segement Register: 00=ES, 01=CS, 10=SS, 11=DS
const LOWER_4BIT_MASK = 0b00001111;
const MODE_MASK: u8 = 0b11000000;
const Register = struct { dest: []const u8, src: []const u8 };

const Instruction = struct {
    op: []const u8 = "mov",
    inst_length: u8,
    wide: bool,
    reg: []const u8,
    sr: []const u8,
    rm: []const u8,
    displacement: u16,
    displacement_length: u8,
    immediate_length: u8,
    immediate: u16,
    address_length: u8,
    address: u16,
    source: Operand,
    destination: Operand,
};

const DecodeError = error{
    InvalidOp,
    InvalidReg,
    InvalidMode,
};

const Operand = enum { REG, RM, SR, IMM, ACC, ADDR };

fn decode_operation(b: []u8) DecodeError!Instruction {
    var instr_length: u8 = 1;
    var direction: bool = false;
    var wide: bool = false;
    var lower_4bit: u8 = 0;
    var mode: u8 = 0;
    var displacement_length: u8 = 0;
    var reg: []const u8 = "";
    var rm: []const u8 = "";
    var sr: []const u8 = "";
    var immediate_length: u8 = 0;
    var address_length: u8 = 0;
    var source: Operand = Operand.REG;
    var destination: Operand = Operand.REG;

    switch (b[0] >> 4) {
        0b1000 => {
            lower_4bit = b[0] & LOWER_4BIT_MASK;
            instr_length = 2;
            switch (lower_4bit) {
                0b1000, 0b1001, 0b1010, 0b1011 => {
                    direction = b[0] & D_BIT > 0;
                    wide = b[0] & W_BIT > 0;
                    mode = b[1] & MODE_MASK;
                    if (direction == false) {
                        source = Operand.REG;
                        destination = Operand.RM;
                    } else {
                        source = Operand.RM;
                        destination = Operand.REG;
                    }

                    switch (mode >> 6) {
                        0 => {
                            if ((b[1] & RM) == 6) {
                                displacement_length = 2;
                                rm = "";
                            } else {
                                rm = try get_rm_prefix(b[1] & RM);
                            }
                        },
                        1 => {
                            rm = try get_rm_prefix(b[1] & RM);
                            displacement_length = 1;
                        },
                        2 => {
                            displacement_length = 2;
                            rm = try get_rm_prefix(b[1] & RM);
                        },
                        3 => {
                            rm = try get_reg_name(b[1] & RM, wide);
                        },
                        else => return DecodeError.InvalidMode,
                    }
                    reg = try get_reg_name((b[1] & REG) >> 3, wide);
                },
                0b1100 => {
                    displacement_length = 2;
                    rm = try get_rm_prefix(b[1] & RM);
                    source = Operand.SR;
                    destination = Operand.RM;
                    sr = try get_sr_name(b[1] & SR);
                },
                0b1110 => {
                    displacement_length = 2;
                    rm = try get_rm_prefix(b[1] & RM);
                    source = Operand.RM;
                    destination = Operand.SR;
                    sr = try get_sr_name(b[1] & SR);
                },
                else => return DecodeError.InvalidOp,
            }
        },
        0b1100 => {
            instr_length = 2;
            if ((b[0] & LOWER_4BIT_MASK) != 0b0110 or (b[0] & LOWER_4BIT_MASK) != 0b0111) {
                return DecodeError.InvalidOp;
            }
            wide = b[0] & W_BIT > 0;
            mode = b[1] & MODE_MASK;
            source = Operand.IMM;
            destination = Operand.RM;
            immediate_length = if (wide) 2 else 1;

            switch (mode >> 6) {
                0 => {
                    if ((b[1] & RM) == 6) {
                        displacement_length = 2;
                        rm = "";
                    } else {
                        rm = try get_rm_prefix(b[1] & RM);
                    }
                },
                1 => {
                    rm = try get_rm_prefix(b[1] & RM);
                    displacement_length = 1;
                },
                2 => {
                    displacement_length = 2;
                    rm = try get_rm_prefix(b[1] & RM);
                },
                3 => {
                    displacement_length = 0;
                    rm = try get_reg_name(b[1] & RM, wide);
                },
                else => return DecodeError.InvalidMode,
            }
        },
        0b1010 => {
            instr_length = 1;
            if (b[0] & LOWER_4BIT_MASK > 3) {
                return DecodeError.InvalidOp;
            }
            wide = b[0] & W_BIT > 0;
            direction = b[0] & D_BIT > 0;
            address_length = if (wide) 2 else 1;
            reg = if (wide) "ax" else "al";
            if (direction == false) {
                source = Operand.ADDR;
                destination = Operand.ACC;
            } else {
                source = Operand.ACC;
                destination = Operand.ADDR;
            }
        },
        0b1011 => {
            instr_length = 1;
            wide = (b[0] & 0b00001000) > 0;
            immediate_length = if (wide) 2 else 1;
            source = Operand.IMM;
            destination = Operand.REG;
            reg = try get_reg_name(b[0] & RM, wide);
        },
        else => return DecodeError.InvalidOp,
    }
    return Instruction{
        .op = "mov",
        .inst_length = instr_length,
        .wide = wide,
        .reg = reg,
        .sr = sr,
        .rm = rm,
        .displacement_length = displacement_length,
        .displacement = 0,
        .immediate_length = immediate_length,
        .immediate = 0,
        .address_length = address_length,
        .address = 0,
        .source = source,
        .destination = destination,
    };
}

fn get_rm_prefix(b: u8) DecodeError![]const u8 {
    var rm_name: []const u8 = "";
    rm_name = switch (b) {
        0 => "bx + si",
        1 => "bx + di",
        2 => "bp + si",
        3 => "bp + di",
        4 => "si",
        5 => "di",
        6 => "", // direct address
        7 => "bx",
        else => return DecodeError.InvalidReg,
    };

    return rm_name;
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

fn get_sr_name(b: u8) DecodeError![]const u8 {
    var sr_name: []const u8 = "";
    sr_name = switch (b) {
        0 => "es",
        1 => "cs",
        2 => "ss",
        3 => "ds",
        else => return DecodeError.InvalidReg,
    };

    return sr_name;
}

fn reverse_read(b: []u8, len: u8) u16 {
    var res: u16 = 0;
    if (len == 2) {
        res = @as(u16, b[1]) << 8 | @as(u16, b[0]);
    } else if (len == 1) {
        res = @as(u16, b[0]);
    }
    return res;
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
    var tmp: []u8 = undefined;
    var name_buffer: [16]u8 = undefined;
    var src_buffer: [128]u8 = undefined;
    var dest_buffer: [128]u8 = undefined;
    var src_text: []const u8 = "";
    var dest_text: []const u8 = "";
    while (i + 1 < bytes_read) {
        var buff_ptr: usize = i;
        tmp = buffer[i .. i + 2];

        var instruction = decode_operation(tmp) catch |err| {
            std.debug.print("Error decoding instruction at byte {}: {}\n", .{ i, err });
            i += 1;
            continue;
        };
        buff_ptr = buff_ptr + instruction.inst_length;

        if (instruction.displacement_length > 0) {
            instruction.displacement = reverse_read(buffer[buff_ptr .. buff_ptr + instruction.displacement_length], instruction.displacement_length);
            if (instruction.rm.len == 0) {
                instruction.rm = try std.fmt.bufPrint(&name_buffer, "[{d}]", .{instruction.displacement});
            } else {
                instruction.rm = try std.fmt.bufPrint(&name_buffer, "[{s} + {d}]", .{ instruction.rm, instruction.displacement });
            }
            buff_ptr = buff_ptr + instruction.displacement_length;
        } else {
            if (instruction.rm.len > 0 and std.mem.containsAtLeast(u8, instruction.rm, 1, "+")) {
                instruction.rm = try std.fmt.bufPrint(&name_buffer, "[{s}]", .{instruction.rm});
            }
        }

        if (instruction.immediate_length > 0) {
            instruction.immediate = reverse_read(buffer[buff_ptr .. buff_ptr + instruction.immediate_length], instruction.immediate_length);
            buff_ptr = buff_ptr + instruction.immediate_length;
        }

        if (instruction.address_length > 0) {
            instruction.address = reverse_read(buffer[buff_ptr .. buff_ptr + instruction.address_length], instruction.address_length);
            buff_ptr = buff_ptr + instruction.address_length;
        }

        src_text = switch (instruction.source) {
            Operand.REG => try std.fmt.bufPrint(&src_buffer, "{s}", .{instruction.reg}),
            Operand.RM => try std.fmt.bufPrint(&src_buffer, "{s}", .{instruction.rm}),
            Operand.SR => try std.fmt.bufPrint(&src_buffer, "{s}", .{instruction.sr}),
            Operand.IMM => try std.fmt.bufPrint(&src_buffer, "{d}", .{instruction.immediate}),
            Operand.ACC => try std.fmt.bufPrint(&src_buffer, "{s}", .{instruction.reg}),
            Operand.ADDR => try std.fmt.bufPrint(&src_buffer, "[{d}]", .{instruction.address}),
        };
        dest_text = switch (instruction.destination) {
            Operand.REG => try std.fmt.bufPrint(&dest_buffer, "{s}", .{instruction.reg}),
            Operand.RM => try std.fmt.bufPrint(&dest_buffer, "{s}", .{instruction.rm}),
            Operand.SR => try std.fmt.bufPrint(&dest_buffer, "{s}", .{instruction.sr}),
            Operand.IMM => try std.fmt.bufPrint(&dest_buffer, "{d}", .{instruction.immediate}),
            Operand.ACC => try std.fmt.bufPrint(&dest_buffer, "{s}", .{instruction.reg}),
            Operand.ADDR => try std.fmt.bufPrint(&dest_buffer, "[{d}]", .{instruction.address}),
        };
        std.debug.print("{s} {s}, {s}\n", .{ instruction.op, dest_text, src_text });
        i = i + instruction.inst_length + instruction.displacement_length + instruction.immediate_length + instruction.address_length;
    }
}
