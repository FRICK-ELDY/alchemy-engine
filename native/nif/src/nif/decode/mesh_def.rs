//! Path: native/nif/src/nif/decode/mesh_def.rs
//! Summary: MeshDef の Elixir リスト → Rust 変換（P3）
//!
//! 形式: [%{name: atom, vertices: [{{x,y,z},{r,g,b,a}}], indices: [0,1,2,...]}, ...]

use super::decode_mesh_vertices;
use render::{MeshDef, MeshVertex};
use rustler::types::list::ListIterator;
use rustler::types::map::MapIterator;
use rustler::{Error as NifError, NifResult, Term};

/// Elixir の mesh_definitions リストをデコードする。
/// 空リスト [] または nil の場合は Ok(vec![]) を返す。
pub fn decode_mesh_definitions(term: Term) -> NifResult<Vec<MeshDef>> {
    // nil の場合は空ベクタを返す（Elixir でオプショナルに nil が渡る場合の対応）
    if term.atom_to_string().as_ref().ok() == Some(&"nil".to_string()) {
        return Ok(vec![]);
    }
    let iter: ListIterator = term.decode().map_err(|_| {
        NifError::Term(Box::new(
            "mesh_definitions: expected list of mesh def maps",
        ))
    })?;
    iter.map(decode_mesh_def).collect()
}

fn decode_mesh_def(term: Term) -> NifResult<MeshDef> {
    let iter = MapIterator::new(term)
        .ok_or_else(|| NifError::Term(Box::new("mesh_def: expected map")))?;

    let mut name: Option<String> = None;
    let mut vertices: Option<Vec<MeshVertex>> = None;
    let mut indices: Option<Vec<u32>> = None;

    for (key, value) in iter {
        let key_str = key
            .atom_to_string()
            .map_err(|_| NifError::Term(Box::new("mesh_def key: expected atom")))?;
        match key_str.as_str() {
            "name" => {
                let s: String = value
                    .decode()
                    .or_else(|_| {
                        value.atom_to_string().map_err(|_| {
                            NifError::Term(Box::new("mesh_def name: expected string or atom"))
                        })
                    })?;
                name = Some(s);
            }
            "vertices" => {
                let verts = decode_mesh_vertices(value, "mesh_def vertices")?;
                vertices = Some(verts);
            }
            "indices" => {
                let idx = decode_indices(value)?;
                indices = Some(idx);
            }
            _ => {}
        }
    }

    let name = name.ok_or_else(|| {
        NifError::Term(Box::new("mesh_def: missing required field 'name'"))
    })?;
    let vertices = vertices.unwrap_or_default();
    let indices = indices.unwrap_or_default();

    Ok(MeshDef {
        name,
        vertices,
        indices,
    })
}

fn decode_indices(term: Term) -> NifResult<Vec<u32>> {
    let iter: ListIterator = term.decode().map_err(|_| {
        NifError::Term(Box::new("mesh_def indices: expected list of non-negative integers"))
    })?;
    let mut out = Vec::new();
    for t in iter {
        let i: u32 = t.decode().map_err(|_| {
            NifError::Term(Box::new("index: expected non-negative integer"))
        })?;
        out.push(i);
    }
    Ok(out)
}
