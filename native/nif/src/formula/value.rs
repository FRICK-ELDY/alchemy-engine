//! Path: native/nif/src/formula/value.rs
//! Summary: Formula VM の値型（f32, i32, bool）

use std::fmt;

#[derive(Debug, Clone, Copy)]
pub enum Value {
    F32(f32),
    I32(i32),
    Bool(bool),
}

impl Value {
    pub fn as_f32(self) -> Option<f32> {
        match self {
            Value::F32(v) => Some(v),
            Value::I32(v) => Some(v as f32),
            Value::Bool(v) => Some(if v { 1.0 } else { 0.0 }),
        }
    }

    pub fn as_i32(self) -> Option<i32> {
        match self {
            Value::F32(v) => Some(v as i32),
            Value::I32(v) => Some(v),
            Value::Bool(v) => Some(if v { 1 } else { 0 }),
        }
    }

    #[allow(dead_code)]
    pub fn as_bool(self) -> Option<bool> {
        match self {
            Value::Bool(v) => Some(v),
            Value::I32(v) => Some(v != 0),
            Value::F32(v) => Some(v != 0.0),
        }
    }

    /// 演算用: 両方を f32 として解釈可能か
    pub fn binary_op_f32(self, rhs: Value) -> Option<(f32, f32)> {
        Some((self.as_f32()?, rhs.as_f32()?))
    }

    /// 演算用: 両方を i32 として解釈可能か
    #[allow(dead_code)]
    pub fn binary_op_i32(self, rhs: Value) -> Option<(i32, i32)> {
        Some((self.as_i32()?, rhs.as_i32()?))
    }

    /// 比較用: 両方を比較可能な数値として解釈
    pub fn compare_f32(self, rhs: Value) -> Option<(f32, f32)> {
        self.binary_op_f32(rhs)
    }
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::F32(v) => write!(f, "{}", v),
            Value::I32(v) => write!(f, "{}", v),
            Value::Bool(v) => write!(f, "{}", v),
        }
    }
}
