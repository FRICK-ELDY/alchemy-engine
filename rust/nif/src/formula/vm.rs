//! Path: native/nif/src/formula/vm.rs
//! Summary: Formula VM（レジスタマシン）の実行

use super::decode::{decode_bytecode, DecodeError, Instruction, REGISTER_COUNT};
use super::value::Value;
use std::collections::HashMap;

#[derive(Debug)]
pub enum VmError {
    Decode(super::decode::DecodeError),
    InputNotFound(String),
    StoreNotFound(String),
    TypeMismatch(String),
    RegisterOutOfRange(u8),
    DivisionByZero,
}

impl From<DecodeError> for VmError {
    fn from(e: DecodeError) -> Self {
        VmError::Decode(e)
    }
}

/// バイトコードを実行し、出力値のリストと更新後の Store を返す。
/// store_values は Elixir が管理する初期値。永続化は Elixir の責務。
pub fn run(
    bytecode: &[u8],
    inputs: &HashMap<String, Value>,
    store_values: &HashMap<String, Value>,
) -> Result<(Vec<Value>, HashMap<String, Value>), VmError> {
    let instructions = decode_bytecode(bytecode)?;
    let mut registers: [Option<Value>; REGISTER_COUNT] = [None; REGISTER_COUNT];
    let mut outputs = Vec::new();
    let mut store = store_values.clone();

    for inst in instructions {
        match inst {
            Instruction::LoadInput { dst, name } => {
                let value = inputs
                    .get(&name)
                    .ok_or_else(|| VmError::InputNotFound(name.clone()))?;
                registers[dst as usize] = Some(*value);
            }
            Instruction::LoadI32 { dst, value } => {
                registers[dst as usize] = Some(Value::I32(value));
            }
            Instruction::LoadF32 { dst, value } => {
                registers[dst as usize] = Some(Value::F32(value));
            }
            Instruction::LoadBool { dst, value } => {
                registers[dst as usize] = Some(Value::Bool(value));
            }
            Instruction::Add { dst, src_a, src_b } => {
                let a = get_register(&registers, src_a)?;
                let b = get_register(&registers, src_b)?;
                let result = binary_add(a, b).ok_or_else(|| VmError::TypeMismatch("add".into()))?;
                registers[dst as usize] = Some(result);
            }
            Instruction::Sub { dst, src_a, src_b } => {
                let a = get_register(&registers, src_a)?;
                let b = get_register(&registers, src_b)?;
                let result = binary_sub(a, b).ok_or_else(|| VmError::TypeMismatch("sub".into()))?;
                registers[dst as usize] = Some(result);
            }
            Instruction::Mul { dst, src_a, src_b } => {
                let a = get_register(&registers, src_a)?;
                let b = get_register(&registers, src_b)?;
                let result = binary_mul(a, b).ok_or_else(|| VmError::TypeMismatch("mul".into()))?;
                registers[dst as usize] = Some(result);
            }
            Instruction::Div { dst, src_a, src_b } => {
                let a = get_register(&registers, src_a)?;
                let b = get_register(&registers, src_b)?;
                let result = binary_div(a, b)?;
                registers[dst as usize] = Some(result);
            }
            Instruction::Lt { dst, src_a, src_b } => {
                let a = get_register(&registers, src_a)?;
                let b = get_register(&registers, src_b)?;
                let result = compare_lt(a, b).ok_or_else(|| VmError::TypeMismatch("lt".into()))?;
                registers[dst as usize] = Some(result);
            }
            Instruction::Gt { dst, src_a, src_b } => {
                let a = get_register(&registers, src_a)?;
                let b = get_register(&registers, src_b)?;
                let result = compare_gt(a, b).ok_or_else(|| VmError::TypeMismatch("gt".into()))?;
                registers[dst as usize] = Some(result);
            }
            Instruction::Eq { dst, src_a, src_b } => {
                let a = get_register(&registers, src_a)?;
                let b = get_register(&registers, src_b)?;
                let result = compare_eq(a, b);
                registers[dst as usize] = Some(result);
            }
            Instruction::StoreOutput { src } => {
                let value = get_register(&registers, src)?;
                outputs.push(value);
            }
            Instruction::ReadStore { dst, name } => {
                let value = store
                    .get(&name)
                    .ok_or_else(|| VmError::StoreNotFound(name.clone()))?;
                registers[dst as usize] = Some(*value);
            }
            Instruction::WriteStore { src, name } => {
                let value = get_register(&registers, src)?;
                store.insert(name, value);
            }
        }
    }

    Ok((outputs, store))
}

fn get_register(registers: &[Option<Value>], r: u8) -> Result<Value, VmError> {
    if r >= REGISTER_COUNT as u8 {
        return Err(VmError::RegisterOutOfRange(r));
    }
    registers[r as usize]
        .ok_or_else(|| VmError::TypeMismatch(format!("register r{} uninitialized", r)))
}

fn binary_add(a: Value, b: Value) -> Option<Value> {
    // 両方 I32 なら I32 で演算。それ以外は F32
    if matches!((a, b), (Value::I32(_), Value::I32(_))) {
        let (va, vb) = (a.as_i32()?, b.as_i32()?);
        return Some(Value::I32(va.saturating_add(vb)));
    }
    let (fa, fb) = a.binary_op_f32(b)?;
    Some(Value::F32(fa + fb))
}

fn binary_sub(a: Value, b: Value) -> Option<Value> {
    if matches!((a, b), (Value::I32(_), Value::I32(_))) {
        let (va, vb) = (a.as_i32()?, b.as_i32()?);
        return Some(Value::I32(va.saturating_sub(vb)));
    }
    let (fa, fb) = a.binary_op_f32(b)?;
    Some(Value::F32(fa - fb))
}

fn binary_mul(a: Value, b: Value) -> Option<Value> {
    if matches!((a, b), (Value::I32(_), Value::I32(_))) {
        let (va, vb) = (a.as_i32()?, b.as_i32()?);
        return Some(Value::I32(va.saturating_mul(vb)));
    }
    let (fa, fb) = a.binary_op_f32(b)?;
    Some(Value::F32(fa * fb))
}

fn binary_div(a: Value, b: Value) -> Result<Value, VmError> {
    if let (Some(va), Some(vb)) = (a.as_i32(), b.as_i32()) {
        if vb == 0 {
            return Err(VmError::DivisionByZero);
        }
        return Ok(Value::I32(va / vb));
    }
    let (fa, fb) = a
        .binary_op_f32(b)
        .ok_or_else(|| VmError::TypeMismatch("div".into()))?;
    if fb == 0.0 {
        return Err(VmError::DivisionByZero);
    }
    Ok(Value::F32(fa / fb))
}

fn compare_lt(a: Value, b: Value) -> Option<Value> {
    let (fa, fb) = a.compare_f32(b)?;
    Some(Value::Bool(fa < fb))
}

fn compare_gt(a: Value, b: Value) -> Option<Value> {
    let (fa, fb) = a.compare_f32(b)?;
    Some(Value::Bool(fa > fb))
}

fn compare_eq(a: Value, b: Value) -> Value {
    // F32 比較は絶対誤差 f32::EPSILON を使用。ゲーム用途で値が小さい場合は許容。
    // 大きい値での比較には相対誤差の検討が必要。
    let result = match (&a, &b) {
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::I32(x), Value::I32(y)) => x == y,
        (Value::F32(x), Value::F32(y)) => (*x - *y).abs() < f32::EPSILON,
        _ => {
            if let (Some(fa), Some(fb)) = (a.as_f32(), b.as_f32()) {
                (fa - fb).abs() < f32::EPSILON
            } else {
                false
            }
        }
    };
    Value::Bool(result)
}
