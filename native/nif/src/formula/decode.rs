//! Path: native/nif/src/formula/decode.rs
//! Summary: バイナリ形式のバイトコードをパースする

use super::opcode::OpCode;
use std::convert::TryInto;

/// デコード後の 1 命令
#[derive(Debug, Clone)]
pub enum Instruction {
    LoadInput { dst: u8, name: String },
    LoadI32 { dst: u8, value: i32 },
    LoadF32 { dst: u8, value: f32 },
    LoadBool { dst: u8, value: bool },
    Add { dst: u8, src_a: u8, src_b: u8 },
    Sub { dst: u8, src_a: u8, src_b: u8 },
    Mul { dst: u8, src_a: u8, src_b: u8 },
    Div { dst: u8, src_a: u8, src_b: u8 },
    Lt { dst: u8, src_a: u8, src_b: u8 },
    Gt { dst: u8, src_a: u8, src_b: u8 },
    Eq { dst: u8, src_a: u8, src_b: u8 },
    StoreOutput { src: u8 },
    ReadStore { dst: u8, name: String },
    WriteStore { src: u8, name: String },
}

pub const REGISTER_COUNT: usize = 64;

#[derive(Debug)]
pub enum DecodeError {
    UnexpectedEof,
    InvalidOpCode(u8),
    RegisterOutOfRange(u8),
    InvalidUtf8,
}

fn ensure_len(buf: &[u8], need: usize) -> Result<(), DecodeError> {
    if buf.len() < need {
        Err(DecodeError::UnexpectedEof)
    } else {
        Ok(())
    }
}

fn check_register(r: u8) -> Result<(), DecodeError> {
    if r >= REGISTER_COUNT as u8 {
        Err(DecodeError::RegisterOutOfRange(r))
    } else {
        Ok(())
    }
}

/// バイト列を命令列にデコードする
pub fn decode_bytecode(bytecode: &[u8]) -> Result<Vec<Instruction>, DecodeError> {
    let mut instructions = Vec::new();
    let mut pos = 0;

    while pos < bytecode.len() {
        ensure_len(&bytecode[pos..], 1)?;
        let op = OpCode::from_u8(bytecode[pos]).ok_or(DecodeError::InvalidOpCode(bytecode[pos]))?;
        pos += 1;

        let inst = match op {
            OpCode::LoadInput => {
                ensure_len(&bytecode[pos..], 2)?;
                let dst = bytecode[pos];
                let name_len = bytecode[pos + 1] as usize;
                pos += 2;
                ensure_len(&bytecode[pos..], name_len)?;
                let name_bytes = &bytecode[pos..pos + name_len];
                pos += name_len;
                let name = String::from_utf8(name_bytes.to_vec())
                    .map_err(|_| DecodeError::InvalidUtf8)?;
                check_register(dst)?;
                Instruction::LoadInput { dst, name }
            }
            OpCode::LoadI32 => {
                ensure_len(&bytecode[pos..], 5)?;
                let dst = bytecode[pos];
                let bytes: [u8; 4] = bytecode[pos + 1..pos + 5]
                    .try_into()
                    .map_err(|_| DecodeError::UnexpectedEof)?;
                let value = i32::from_le_bytes(bytes);
                pos += 5;
                check_register(dst)?;
                Instruction::LoadI32 { dst, value }
            }
            OpCode::LoadF32 => {
                ensure_len(&bytecode[pos..], 5)?;
                let dst = bytecode[pos];
                let bytes: [u8; 4] = bytecode[pos + 1..pos + 5]
                    .try_into()
                    .map_err(|_| DecodeError::UnexpectedEof)?;
                let value = f32::from_le_bytes(bytes);
                pos += 5;
                check_register(dst)?;
                Instruction::LoadF32 { dst, value }
            }
            OpCode::LoadBool => {
                ensure_len(&bytecode[pos..], 2)?;
                let dst = bytecode[pos];
                let value = bytecode[pos + 1] != 0;
                pos += 2;
                check_register(dst)?;
                Instruction::LoadBool { dst, value }
            }
            OpCode::Add | OpCode::Sub | OpCode::Mul | OpCode::Div
            | OpCode::Lt | OpCode::Gt | OpCode::Eq => {
                ensure_len(&bytecode[pos..], 3)?;
                let dst = bytecode[pos];
                let src_a = bytecode[pos + 1];
                let src_b = bytecode[pos + 2];
                pos += 3;
                check_register(dst)?;
                check_register(src_a)?;
                check_register(src_b)?;
                match op {
                    OpCode::Add => Instruction::Add { dst, src_a, src_b },
                    OpCode::Sub => Instruction::Sub { dst, src_a, src_b },
                    OpCode::Mul => Instruction::Mul { dst, src_a, src_b },
                    OpCode::Div => Instruction::Div { dst, src_a, src_b },
                    OpCode::Lt => Instruction::Lt { dst, src_a, src_b },
                    OpCode::Gt => Instruction::Gt { dst, src_a, src_b },
                    OpCode::Eq => Instruction::Eq { dst, src_a, src_b },
                    _ => unreachable!(),
                }
            }
            OpCode::StoreOutput => {
                ensure_len(&bytecode[pos..], 1)?;
                let src = bytecode[pos];
                pos += 1;
                check_register(src)?;
                Instruction::StoreOutput { src }
            }
            OpCode::ReadStore => {
                ensure_len(&bytecode[pos..], 2)?;
                let dst = bytecode[pos];
                let name_len = bytecode[pos + 1] as usize;
                pos += 2;
                ensure_len(&bytecode[pos..], name_len)?;
                let name_bytes = &bytecode[pos..pos + name_len];
                pos += name_len;
                let name = String::from_utf8(name_bytes.to_vec())
                    .map_err(|_| DecodeError::InvalidUtf8)?;
                check_register(dst)?;
                Instruction::ReadStore { dst, name }
            }
            OpCode::WriteStore => {
                ensure_len(&bytecode[pos..], 2)?;
                let src = bytecode[pos];
                let name_len = bytecode[pos + 1] as usize;
                pos += 2;
                ensure_len(&bytecode[pos..], name_len)?;
                let name_bytes = &bytecode[pos..pos + name_len];
                pos += name_len;
                let name = String::from_utf8(name_bytes.to_vec())
                    .map_err(|_| DecodeError::InvalidUtf8)?;
                check_register(src)?;
                Instruction::WriteStore { src, name }
            }
        };

        instructions.push(inst);
    }

    Ok(instructions)
}
