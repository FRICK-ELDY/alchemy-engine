//! Path: native/nif/src/formula/opcode.rs
//! Summary: Formula VM の OpCode 定義

/// OpCode バイト値。バイナリ形式のバイトコードで使用。
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpCode {
    /// 入力値をレジスタへ。オペランド: dst, name_len, name_bytes...
    LoadInput = 0,
    /// 定数 i32 をレジスタへ。オペランド: dst, i32_le
    LoadI32 = 1,
    /// 定数 f32 をレジスタへ。オペランド: dst, f32_le
    LoadF32 = 2,
    /// 定数 bool をレジスタへ。オペランド: dst, u8 (0=false, 1=true)
    LoadBool = 3,
    /// r_dst = r_a + r_b
    Add = 4,
    /// r_dst = r_a - r_b
    Sub = 5,
    /// r_dst = r_a * r_b
    Mul = 6,
    /// r_dst = r_a / r_b
    Div = 7,
    /// r_dst = (r_a < r_b)
    Lt = 8,
    /// r_dst = (r_a > r_b)
    Gt = 9,
    /// r_dst = (r_a == r_b)
    Eq = 10,
    /// レジスタ値を出力に追加
    StoreOutput = 11,
    /// Store からキーで読んでレジスタへ。オペランド: dst, key_len, key_bytes...
    ReadStore = 12,
    /// レジスタ値を Store に書き込む。オペランド: src, key_len, key_bytes...
    WriteStore = 13,
}

impl OpCode {
    pub fn from_u8(b: u8) -> Option<Self> {
        match b {
            0 => Some(OpCode::LoadInput),
            1 => Some(OpCode::LoadI32),
            2 => Some(OpCode::LoadF32),
            3 => Some(OpCode::LoadBool),
            4 => Some(OpCode::Add),
            5 => Some(OpCode::Sub),
            6 => Some(OpCode::Mul),
            7 => Some(OpCode::Div),
            8 => Some(OpCode::Lt),
            9 => Some(OpCode::Gt),
            10 => Some(OpCode::Eq),
            11 => Some(OpCode::StoreOutput),
            12 => Some(OpCode::ReadStore),
            13 => Some(OpCode::WriteStore),
            _ => None,
        }
    }
}
