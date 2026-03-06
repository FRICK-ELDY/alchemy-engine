//! Path: native/nif/src/nif/formula_nif.rs
//! Summary: run_formula_bytecode NIF — バイトコードを実行し結果を返す
//!
//! ドメインエラー（input_not_found, division_by_zero 等）は NIF としては成功とし、
//! Ok({:error, reason_atom, detail}) を返す。他 NIF の NifResult::Err は NIF 層の異常用。

use crate::formula::{run, Value, VmError};
use rustler::types::map::MapIterator;
use rustler::{Encoder, Env, NifResult, Term};
use std::collections::HashMap;

enum InputDecodeError {
    IntegerOutOfRange(i64),
    ExpectedMap,
    InvalidKey,
    InvalidValue,
}

/// バイトコードと入力マップ・Store 初期値を受け取り、出力と更新後の Store を返す。
///
/// - bytecode: バイナリ形式のバイトコード
/// - inputs: %{"name" => value} 形式のマップ。value は integer | float | boolean
/// - store_values: Store の初期値。%{"key" => value}。READ_STORE で参照するキーは事前に含めること。
///
/// 戻り値: {:ok, {outputs, updated_store}} | {:error, reason_atom, detail}
#[rustler::nif]
pub fn run_formula_bytecode<'a>(
    env: Env<'a>,
    bytecode: rustler::Binary<'a>,
    inputs: Term<'a>,
    store_values: Term<'a>,
) -> NifResult<Term<'a>> {
    let input_map = match decode_input_map(inputs) {
        Ok(m) => m,
        Err(InputDecodeError::IntegerOutOfRange(v)) => {
            let err_term = input_error_to_term(env, &InputDecodeError::IntegerOutOfRange(v))?;
            return Ok(err_term);
        }
        Err(InputDecodeError::ExpectedMap) => {
            return Err(rustler::Error::Term(Box::new("inputs: expected map")));
        }
        Err(InputDecodeError::InvalidKey) => {
            return Err(rustler::Error::Term(Box::new(
                "input key: expected string or atom",
            )));
        }
        Err(InputDecodeError::InvalidValue) => {
            return Err(rustler::Error::Term(Box::new(
                "input value: expected integer (i32 range), float, or boolean",
            )));
        }
    };
    let store_map = decode_value_map(store_values).map_err(|e| match e {
        InputDecodeError::IntegerOutOfRange(v) => rustler::Error::Term(Box::new(format!(
            "store value: integer {} out of i32 range",
            v
        ))),
        InputDecodeError::ExpectedMap => {
            rustler::Error::Term(Box::new("store_values: expected map"))
        }
        InputDecodeError::InvalidKey => {
            rustler::Error::Term(Box::new("store key: expected string or atom"))
        }
        InputDecodeError::InvalidValue => rustler::Error::Term(Box::new(
            "store value: expected integer (i32 range), float, or boolean",
        )),
    })?;
    match run(bytecode.as_slice(), &input_map, &store_map) {
        Ok((outputs, updated_store)) => {
            let terms: Vec<Term<'a>> = outputs.iter().map(|v| value_to_term(env, v)).collect();
            let store_terms = map_value_map_to_elixir(env, &updated_store);
            let ok_atom = rustler::Atom::from_str(env, "ok")?;
            Ok((ok_atom, (terms, store_terms)).encode(env))
        }
        Err(e) => {
            let err_term = error_to_term(env, e)?;
            Ok(err_term)
        }
    }
}

fn decode_value_map(term: Term) -> Result<HashMap<String, Value>, InputDecodeError> {
    let iter = MapIterator::new(term).ok_or(InputDecodeError::ExpectedMap)?;
    let mut map = HashMap::new();
    for (key_term, value_term) in iter {
        let key = term_to_string(key_term).map_err(|_| InputDecodeError::InvalidKey)?;
        let value = term_to_value(value_term)?;
        map.insert(key, value);
    }
    Ok(map)
}

fn decode_input_map(term: Term) -> Result<HashMap<String, Value>, InputDecodeError> {
    decode_value_map(term)
}

fn map_value_map_to_elixir<'a>(env: Env<'a>, map: &HashMap<String, Value>) -> rustler::Term<'a> {
    let pairs: Vec<(String, StoreEncodable)> = map
        .iter()
        .map(|(k, v)| (k.clone(), value_to_store_encodable(v)))
        .collect();
    pairs.encode(env)
}

#[derive(Clone, Copy)]
enum StoreEncodable {
    I32(i32),
    F64(f64),
    Bool(bool),
}

impl rustler::Encoder for StoreEncodable {
    fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a> {
        match self {
            StoreEncodable::I32(x) => x.encode(env),
            StoreEncodable::F64(x) => x.encode(env),
            StoreEncodable::Bool(x) => x.encode(env),
        }
    }
}

fn value_to_store_encodable(v: &Value) -> StoreEncodable {
    match v {
        Value::I32(x) => StoreEncodable::I32(*x),
        Value::F32(x) => StoreEncodable::F64(*x as f64),
        Value::Bool(x) => StoreEncodable::Bool(*x),
    }
}

fn term_to_string(term: Term) -> NifResult<String> {
    if term.is_atom() {
        term.atom_to_string()
            .map_err(|_| rustler::Error::Term(Box::new("input key: expected string or atom")))
    } else if term.is_binary() {
        let s: String = term
            .decode()
            .map_err(|_| rustler::Error::Term(Box::new("input key: expected string")))?;
        Ok(s)
    } else {
        Err(rustler::Error::Term(Box::new(
            "input key: expected string or atom",
        )))
    }
}

fn term_to_value(term: Term) -> Result<Value, InputDecodeError> {
    if let Ok(i) = term.decode::<i32>() {
        return Ok(Value::I32(i));
    }
    if let Ok(i) = term.decode::<i64>() {
        let v = i32::try_from(i).map_err(|_| InputDecodeError::IntegerOutOfRange(i))?;
        return Ok(Value::I32(v));
    }
    if let Ok(f) = term.decode::<f64>() {
        return Ok(Value::F32(f as f32));
    }
    if let Ok(b) = term.decode::<bool>() {
        return Ok(Value::Bool(b));
    }
    Err(InputDecodeError::InvalidValue)
}

fn input_error_to_term<'a>(env: Env<'a>, e: &InputDecodeError) -> NifResult<Term<'a>> {
    let err_atom = rustler::Atom::from_str(env, "error")?;
    let (reason, detail): (rustler::Atom, Term) = match e {
        InputDecodeError::IntegerOutOfRange(v) => (
            rustler::Atom::from_str(env, "integer_out_of_range")?,
            (*v).encode(env),
        ),
        _ => unreachable!("input_error_to_term only handles IntegerOutOfRange"),
    };
    Ok((err_atom, reason, detail).encode(env))
}

fn value_to_term<'a>(env: Env<'a>, v: &Value) -> Term<'a> {
    match v {
        Value::F32(x) => (*x as f64).encode(env),
        Value::I32(x) => x.encode(env),
        Value::Bool(x) => x.encode(env),
    }
}

/// エラーは常に 3 要素タプル {:error, reason_atom, detail} に統一。
/// detail が不要な場合は nil を渡す。
fn error_to_term<'a>(env: Env<'a>, e: VmError) -> NifResult<Term<'a>> {
    let err_atom = rustler::Atom::from_str(env, "error")?;
    let nil_term: Term = None::<i32>.encode(env);

    let (reason, detail): (rustler::Atom, Term) = match e {
        VmError::Decode(de) => match de {
            crate::formula::DecodeError::UnexpectedEof => {
                (rustler::Atom::from_str(env, "unexpected_eof")?, nil_term)
            }
            crate::formula::DecodeError::InvalidOpCode(b) => (
                rustler::Atom::from_str(env, "invalid_opcode")?,
                b.encode(env),
            ),
            crate::formula::DecodeError::RegisterOutOfRange(r) => (
                rustler::Atom::from_str(env, "register_out_of_range")?,
                r.encode(env),
            ),
            crate::formula::DecodeError::InvalidUtf8 => {
                (rustler::Atom::from_str(env, "invalid_utf8")?, nil_term)
            }
        },
        VmError::InputNotFound(name) => (
            rustler::Atom::from_str(env, "input_not_found")?,
            name.encode(env),
        ),
        VmError::StoreNotFound(name) => (
            rustler::Atom::from_str(env, "store_not_found")?,
            name.encode(env),
        ),
        VmError::TypeMismatch(msg) => (
            rustler::Atom::from_str(env, "type_mismatch")?,
            msg.encode(env),
        ),
        VmError::RegisterOutOfRange(r) => (
            rustler::Atom::from_str(env, "register_out_of_range")?,
            r.encode(env),
        ),
        VmError::DivisionByZero => (rustler::Atom::from_str(env, "division_by_zero")?, nil_term),
    };

    Ok((err_atom, reason, detail).encode(env))
}
