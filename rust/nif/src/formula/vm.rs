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
    // 両方 I32 なら I32 で演算。それ以外は F32（加減乗と揃える）
    // as_i32() は F32 も truncate して Some を返すため、型を先に判定する。
    if let (Value::I32(va), Value::I32(vb)) = (a, b) {
        if vb == 0 {
            return Err(VmError::DivisionByZero);
        }
        // checked_div: i32::MIN / -1 のオーバーフローを封じる（saturating 方針）
        return Ok(Value::I32(va.checked_div(vb).unwrap_or(i32::MAX)));
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn load_i32(dst: u8, value: i32) -> Vec<u8> {
        let mut buf = vec![1u8, dst]; // OpCode::LoadI32
        buf.extend_from_slice(&value.to_le_bytes());
        buf
    }

    fn load_f32(dst: u8, value: f32) -> Vec<u8> {
        let mut buf = vec![2u8, dst]; // OpCode::LoadF32
        buf.extend_from_slice(&value.to_le_bytes());
        buf
    }

    fn div(dst: u8, src_a: u8, src_b: u8) -> Vec<u8> {
        vec![7u8, dst, src_a, src_b] // OpCode::Div
    }

    fn store_output(src: u8) -> Vec<u8> {
        vec![11u8, src] // OpCode::StoreOutput
    }

    fn run_empty(bytecode: &[u8]) -> Result<Vec<Value>, VmError> {
        let (outputs, _) = run(bytecode, &HashMap::new(), &HashMap::new())?;
        Ok(outputs)
    }

    #[test]
    fn div_f32_returns_float() {
        // 5.0 / 2.0 → F32(2.5)（整数除算に化けないこと）
        let mut bc = Vec::new();
        bc.extend(load_f32(0, 5.0));
        bc.extend(load_f32(1, 2.0));
        bc.extend(div(2, 0, 1));
        bc.extend(store_output(2));

        let outputs = run_empty(&bc).expect("run");
        assert_eq!(outputs.len(), 1);
        match outputs[0] {
            Value::F32(v) => assert!((v - 2.5).abs() < f32::EPSILON, "got {}", v),
            other => panic!("expected F32(2.5), got {:?}", other),
        }
    }

    #[test]
    fn div_i32_keeps_integer() {
        let mut bc = Vec::new();
        bc.extend(load_i32(0, 7));
        bc.extend(load_i32(1, 2));
        bc.extend(div(2, 0, 1));
        bc.extend(store_output(2));

        let outputs = run_empty(&bc).expect("run");
        assert!(matches!(outputs.as_slice(), [Value::I32(3)]));
    }

    #[test]
    fn div_mixed_promotes_to_f32() {
        // I32 / F32 → F32
        let mut bc = Vec::new();
        bc.extend(load_i32(0, 5));
        bc.extend(load_f32(1, 2.0));
        bc.extend(div(2, 0, 1));
        bc.extend(store_output(2));

        let outputs = run_empty(&bc).expect("run");
        match outputs[0] {
            Value::F32(v) => assert!((v - 2.5).abs() < f32::EPSILON, "got {}", v),
            other => panic!("expected F32(2.5), got {:?}", other),
        }
    }

    #[test]
    fn div_i32_min_by_neg_one_does_not_panic() {
        // i32::MIN / -1 → saturating で i32::MAX（パニックしない）
        let mut bc = Vec::new();
        bc.extend(load_i32(0, i32::MIN));
        bc.extend(load_i32(1, -1));
        bc.extend(div(2, 0, 1));
        bc.extend(store_output(2));

        let outputs = run_empty(&bc).expect("run must not panic");
        assert!(matches!(outputs.as_slice(), [Value::I32(i32::MAX)]));
    }

    #[test]
    fn div_by_zero_i32_errors() {
        let mut bc = Vec::new();
        bc.extend(load_i32(0, 1));
        bc.extend(load_i32(1, 0));
        bc.extend(div(2, 0, 1));
        bc.extend(store_output(2));

        assert!(matches!(run_empty(&bc), Err(VmError::DivisionByZero)));
    }

    #[test]
    fn div_by_zero_f32_errors() {
        let mut bc = Vec::new();
        bc.extend(load_f32(0, 1.0));
        bc.extend(load_f32(1, 0.0));
        bc.extend(div(2, 0, 1));
        bc.extend(store_output(2));

        assert!(matches!(run_empty(&bc), Err(VmError::DivisionByZero)));
    }
}
