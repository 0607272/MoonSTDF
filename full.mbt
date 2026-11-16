///|
/// Physical values, before sentinels/defaults are interpreted by analysis.
#derive(Debug)
pub(all) enum V4Value {
  MissingField
  UnsignedField(UInt32)
  SignedField(Int32)
  RealField(Double)
  TextField(String)
  BytesField(Bytes)
  BitsField(Int32, Bytes)
  ArrayField(Array[V4Value])
  GenericField(Array[GenericValue])
}

///|
#derive(Debug)
pub(all) struct V4Field {
  name : String
  value : V4Value
}

///|
/// All standard fields in wire order, including explicitly missing suffixes.
#derive(Debug)
pub(all) struct V4Record {
  name : String
  fields : Array[V4Field]
  frame : Frame
}

///|
pub fn V4Record::field(self : V4Record, name : String) -> V4Value? {
  for field in self.fields {
    if field.name == name {
      return Some(field.value)
    }
  }
  None
}

///|
/// Names, field layouts and required prefix lengths transcribed from base V4.
/// @COUNT denotes an array; its count is a preceding scalar field.
fn v4_layout(typ : Int32, sub : Int32) -> (String, String, Int32)? {
  match (typ, sub) {
    (0, 10) => Some(("FAR", "CPU_TYPE:u1 STDF_VER:u1", 2))
    (0, 20) => Some(("ATR", "MOD_TIM:u4 CMD_LINE:cn", 2))
    (1, 10) =>
      Some(
        (
          "MIR", "SETUP_T:u4 START_T:u4 STAT_NUM:u1 MODE_COD:c1 RTST_COD:c1 PROT_COD:c1 BURN_TIM:u2 CMOD_COD:c1 LOT_ID:cn PART_TYP:cn NODE_NAM:cn TSTR_TYP:cn JOB_NAM:cn JOB_REV:cn SBLOT_ID:cn OPER_NAM:cn EXEC_TYP:cn EXEC_VER:cn TEST_COD:cn TST_TEMP:cn USER_TXT:cn AUX_FILE:cn PKG_TYP:cn FAMLY_ID:cn DATE_COD:cn FACIL_ID:cn FLOOR_ID:cn PROC_ID:cn OPER_FRQ:cn SPEC_NAM:cn SPEC_VER:cn FLOW_ID:cn SETUP_ID:cn DSGN_REV:cn ENG_ID:cn ROM_COD:cn SERL_NUM:cn SUPR_NAM:cn",
          13,
        ),
      )
    (1, 20) =>
      Some(("MRR", "FINISH_T:u4 DISP_COD:c1 USR_DESC:cn EXC_DESC:cn", 1))
    (1, 30) =>
      Some(
        (
          "PCR", "HEAD_NUM:u1 SITE_NUM:u1 PART_CNT:u4 RTST_CNT:u4 ABRT_CNT:u4 GOOD_CNT:u4 FUNC_CNT:u4",
          3,
        ),
      )
    (1, 40) =>
      Some(
        (
          "HBR", "HEAD_NUM:u1 SITE_NUM:u1 HBIN_NUM:u2 HBIN_CNT:u4 HBIN_PF:c1 HBIN_NAM:cn",
          4,
        ),
      )
    (1, 50) =>
      Some(
        (
          "SBR", "HEAD_NUM:u1 SITE_NUM:u1 SBIN_NUM:u2 SBIN_CNT:u4 SBIN_PF:c1 SBIN_NAM:cn",
          4,
        ),
      )
    (1, 60) =>
      Some(
        (
          "PMR", "PMR_INDX:u2 CHAN_TYP:u2 CHAN_NAM:cn PHY_NAM:cn LOG_NAM:cn HEAD_NUM:u1 SITE_NUM:u1",
          1,
        ),
      )
    (1, 62) =>
      Some(
        ("PGR", "GRP_INDX:u2 GRP_NAM:cn INDX_CNT:u2 PMR_INDX:u2@INDX_CNT", 3),
      )
    (1, 63) =>
      Some(
        (
          "PLR", "GRP_CNT:u2 GRP_INDX:u2@GRP_CNT GRP_MODE:u2@GRP_CNT GRP_RADX:u1@GRP_CNT PGM_CHAR:cn@GRP_CNT RTN_CHAR:cn@GRP_CNT PGM_CHAL:cn@GRP_CNT RTN_CHAL:cn@GRP_CNT",
          2,
        ),
      )
    (1, 70) => Some(("RDR", "NUM_BINS:u2 RTST_BIN:u2@NUM_BINS", 1))
    (1, 80) =>
      Some(
        (
          "SDR", "HEAD_NUM:u1 SITE_GRP:u1 SITE_CNT:u1 SITE_NUM:u1@SITE_CNT HAND_TYP:cn HAND_ID:cn CARD_TYP:cn CARD_ID:cn LOAD_TYP:cn LOAD_ID:cn DIB_TYP:cn DIB_ID:cn CABL_TYP:cn CABL_ID:cn CONT_TYP:cn CONT_ID:cn LASR_TYP:cn LASR_ID:cn EXTR_TYP:cn EXTR_ID:cn",
          4,
        ),
      )
    (2, 10) =>
      Some(("WIR", "HEAD_NUM:u1 SITE_GRP:u1 START_T:u4 WAFER_ID:cn", 3))
    (2, 20) =>
      Some(
        (
          "WRR", "HEAD_NUM:u1 SITE_GRP:u1 FINISH_T:u4 PART_CNT:u4 RTST_CNT:u4 ABRT_CNT:u4 GOOD_CNT:u4 FUNC_CNT:u4 WAFER_ID:cn FABWF_ID:cn FRAME_ID:cn MASK_ID:cn USR_DESC:cn EXC_DESC:cn",
          4,
        ),
      )
    (2, 30) =>
      Some(
        (
          "WCR", "WAFR_SIZ:r4 DIE_HT:r4 DIE_WID:r4 WF_UNITS:u1 WF_FLAT:c1 CENTER_X:i2 CENTER_Y:i2 POS_X:c1 POS_Y:c1",
          0,
        ),
      )
    (5, 10) => Some(("PIR", "HEAD_NUM:u1 SITE_NUM:u1", 2))
    (5, 20) =>
      Some(
        (
          "PRR", "HEAD_NUM:u1 SITE_NUM:u1 PART_FLG:u1 NUM_TEST:u2 HARD_BIN:u2 SOFT_BIN:u2 X_COORD:i2 Y_COORD:i2 TEST_T:u4 PART_ID:cn PART_TXT:cn PART_FIX:bn",
          5,
        ),
      )
    (10, 30) =>
      Some(
        (
          "TSR", "HEAD_NUM:u1 SITE_NUM:u1 TEST_TYP:c1 TEST_NUM:u4 EXEC_CNT:u4 FAIL_CNT:u4 ALRM_CNT:u4 TEST_NAM:cn SEQ_NAME:cn TEST_LBL:cn OPT_FLAG:u1 TEST_TIM:r4 TEST_MIN:r4 TEST_MAX:r4 TST_SUMS:r4 TST_SQRS:r4",
          4,
        ),
      )
    (15, 10) =>
      Some(
        (
          "PTR", "TEST_NUM:u4 HEAD_NUM:u1 SITE_NUM:u1 TEST_FLG:u1 PARM_FLG:u1 RESULT:r4 TEST_TXT:cn ALARM_ID:cn OPT_FLAG:u1 RES_SCAL:i1 LLM_SCAL:i1 HLM_SCAL:i1 LO_LIMIT:r4 HI_LIMIT:r4 UNITS:cn C_RESFMT:cn C_LLMFMT:cn C_HLMFMT:cn LO_SPEC:r4 HI_SPEC:r4",
          5,
        ),
      )
    (15, 15) =>
      Some(
        (
          "MPR", "TEST_NUM:u4 HEAD_NUM:u1 SITE_NUM:u1 TEST_FLG:u1 PARM_FLG:u1 RTN_ICNT:u2 RSLT_CNT:u2 RTN_STAT:n1@RTN_ICNT RTN_RSLT:r4@RSLT_CNT TEST_TXT:cn ALARM_ID:cn OPT_FLAG:u1 RES_SCAL:i1 LLM_SCAL:i1 HLM_SCAL:i1 LO_LIMIT:r4 HI_LIMIT:r4 START_IN:r4 INCR_IN:r4 RTN_INDX:u2@RTN_ICNT UNITS:cn UNITS_IN:cn C_RESFMT:cn C_LLMFMT:cn C_HLMFMT:cn LO_SPEC:r4 HI_SPEC:r4",
          5,
        ),
      )
    (15, 20) =>
      Some(
        (
          "FTR", "TEST_NUM:u4 HEAD_NUM:u1 SITE_NUM:u1 TEST_FLG:u1 OPT_FLAG:u1 CYCL_CNT:u4 REL_VADR:u4 REPT_CNT:u4 NUM_FAIL:u4 XFAIL_AD:i4 YFAIL_AD:i4 VECT_OFF:i2 RTN_ICNT:u2 PGM_ICNT:u2 RTN_INDX:u2@RTN_ICNT RTN_STAT:n1@RTN_ICNT PGM_INDX:u2@PGM_ICNT PGM_STAT:n1@PGM_ICNT FAIL_PIN:dn VECT_NAM:cn TIME_SET:cn OP_CODE:cn TEST_TXT:cn ALARM_ID:cn PROG_TXT:cn RSLT_TXT:cn PATG_NUM:u1 SPIN_MAP:dn",
          4,
        ),
      )
    (20, 10) => Some(("BPS", "SEQ_NAME:cn", 0))
    (20, 20) => Some(("EPS", "", 0))
    (50, 10) => Some(("GDR", "FLD_CNT:u2 GEN_DATA:generic@FLD_CNT", 1))
    (50, 30) => Some(("DTR", "TEXT_DAT:cn", 1))
    _ => None
  }
}

///|
fn v4_scalar(r : Reader, kind : String) -> V4Value raise StdfError {
  match kind {
    "u1" => UnsignedField(r.u1().reinterpret_as_uint())
    "u2" => UnsignedField(r.u2().reinterpret_as_uint())
    "u4" => UnsignedField(r.u4())
    "i1" => SignedField(r.i1())
    "i2" => SignedField(r.i2())
    "i4" => SignedField(r.u4().reinterpret_as_int())
    "r4" => RealField(r.r4())
    "r8" => RealField(r.r8())
    "c1" => TextField(r.u1().to_char().unwrap().to_string())
    "cn" => TextField(r.cn())
    "bn" => BytesField(r.take(r.u1()))
    "dn" => {
      let bits = r.u2()
      let bytes = r.take((bits + 7) / 8)
      if bits % 8 != 0 && bytes[bytes.length() - 1].to_int() >> (bits % 8) != 0 {
        raise StdfError(r.base + r.pos - 1, "nonzero D*n padding")
      }
      BitsField(bits, bytes)
    }
    _ => raise StdfError(r.base + r.pos, "invalid internal V4 field layout")
  }
}

///|
/// Complete named-field reader for all 25 base V4 record IDs. Unknown records
/// return None and remain available as raw Frame values. No source bytes lost.
pub fn decode_v4_record(frame : Frame) -> V4Record? raise StdfError {
  validate_frame(frame)
  guard v4_layout(frame.typ, frame.sub) is Some((name, layout, required)) else {
    return None
  }
  let r = Reader::new(frame.body, frame.order, frame.offset + 4)
  let fields : Array[V4Field] = []
  let counts : Map[String, Int32] = Map([])
  if layout != "" {
    for index, token in layout.split(" ").collect() {
      let definition = token.split(":").collect()
      let field_name = definition[0].to_owned()
      let wire = definition[1].split("@").collect()
      let kind = wire[0].to_owned()
      let count = if wire.length() == 2 {
        counts.get(wire[1].to_owned()).unwrap_or(0)
      } else {
        0
      }
      let is_array = wire.length() == 2
      let value = if is_array && kind == "generic" {
        let values = []
        for _ in 0..<count {
          values.push(gdr_value(r))
        }
        GenericField(values)
      } else if is_array && kind == "n1" {
        let packed = r.take((count + 1) / 2)
        let values = []
        for i in 0..<count {
          let byte = packed[i / 2].to_int()
          values.push(
            UnsignedField(
              (if i % 2 == 0 { byte & 15 } else { byte >> 4 }).reinterpret_as_uint(),
            ),
          )
        }
        if count % 2 == 1 && packed[packed.length() - 1].to_int() >> 4 != 0 {
          raise StdfError(r.base + r.pos - 1, "nonzero N*1 array padding")
        }
        ArrayField(values)
      } else if r.remaining() == 0 && index >= required {
        // Nonzero mandatory arrays cannot be hidden by a missing suffix.
        if is_array &&
          count > 0 &&
          (
            field_name == "PMR_INDX" ||
            field_name == "RTST_BIN" ||
            field_name == "RTN_RSLT"
          ) {
          raise StdfError(r.base + r.pos, "missing counted array")
        }
        MissingField
      } else if is_array {
        let values = []
        for _ in 0..<count {
          if r.remaining() == 0 && name == "PLR" && field_name != "GRP_INDX" {
            values.push(MissingField)
          } else {
            values.push(v4_scalar(r, kind))
          }
        }
        ArrayField(values)
      } else {
        v4_scalar(r, kind)
      }
      if value is UnsignedField(n) && n <= 65535U {
        counts[field_name] = n.reinterpret_as_int()
      }
      fields.push({ name: field_name, value, })
    }
  }
  r.end()
  let record = { name, fields, frame, }
  if name == "PTR" &&
    record.field("RESULT") is Some(MissingField) &&
    record.field("TEST_FLG") is Some(UnsignedField(flags)) &&
    (flags & 2U) == 0U {
    raise StdfError(frame.offset + 12, "PTR requires valid RESULT")
  }
  Some(record)
}

///|
pub extend V4Value with @debug.Debug::{to_repr}

///|
pub extend V4Field with @debug.Debug::{to_repr}

///|
pub extend V4Record with @debug.Debug::{to_repr}
