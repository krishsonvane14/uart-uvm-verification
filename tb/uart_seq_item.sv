// =============================================================================
// uart_seq_item.sv — UVM Sequence Item for UART Transactions
// =============================================================================
// Represents one UART frame: the payload byte plus parity configuration and
// optional error-injection controls used by the driver to corrupt a frame.
//
// Scoreboard comparison covers only the observable outputs (data, parity_en,
// parity_type). The inject_* fields are stimulus intent — they describe what
// the driver did, not what the receiver should report — so they carry
// UVM_NOCOMPARE but remain copyable and printable for debug.
// =============================================================================
`include "uvm_macros.svh"
import uvm_pkg::*;

class uart_seq_item extends uvm_sequence_item;

    // -----------------------------------------------------------------------
    // Factory registration and field automation
    // -----------------------------------------------------------------------
    `uvm_object_utils_begin(uart_seq_item)
        `uvm_field_int(data,                 UVM_ALL_ON)
        `uvm_field_int(parity_en,            UVM_ALL_ON)
        `uvm_field_int(parity_type,          UVM_ALL_ON)
        `uvm_field_int(inject_framing_error, UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(inject_noise,         UVM_ALL_ON | UVM_NOCOMPARE)
        `uvm_field_int(noise_bit_pos,        UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_object_utils_end

    // -----------------------------------------------------------------------
    // Transaction fields
    // -----------------------------------------------------------------------
    rand logic [7:0] data;                // payload byte
    rand logic       parity_en;           // enable parity for this frame
    rand logic       parity_type;         // 0=even 1=odd
    rand logic       inject_framing_error;// driver pulls stop bit low
    rand logic       inject_noise;        // driver glitches one data bit
    rand logic [2:0] noise_bit_pos;       // which data bit (0–7) to glitch

    // -----------------------------------------------------------------------
    // Constraints
    // -----------------------------------------------------------------------

    // Error injection is off by default so unconstrained random tests stay
    // clean. Sequences that need error coverage disable this constraint.
    constraint c_no_error_default {
        inject_framing_error == 1'b0;
        inject_noise         == 1'b0;
    }

    // noise_bit_pos is 3 bits so it naturally covers 0–7, but the explicit
    // constraint documents the intended range and guards against future
    // widening of the field.
    constraint c_noise_pos_valid {
        noise_bit_pos inside {[0:7]};
    }

    // Injecting both error types simultaneously is undefined — the driver
    // has no specification for which takes precedence.
    constraint c_mutual_exclusion {
        !(inject_framing_error && inject_noise);
    }

    // -----------------------------------------------------------------------
    // new
    // -----------------------------------------------------------------------
    function new(string name = "uart_seq_item");
        super.new(name);
    endfunction

    // -----------------------------------------------------------------------
    // do_copy — explicit deep copy of all fields
    // super.do_copy handles uvm_sequence_item housekeeping (sequencer links
    // etc.), then we copy every field ourselves.
    // -----------------------------------------------------------------------
    function void do_copy(uvm_object rhs);
        uart_seq_item rhs_cast;
        if (!$cast(rhs_cast, rhs))
            `uvm_fatal("UART_SEQ_ITEM/COPY", "rhs is not of type uart_seq_item")
        super.do_copy(rhs);
        data                 = rhs_cast.data;
        parity_en            = rhs_cast.parity_en;
        parity_type          = rhs_cast.parity_type;
        inject_framing_error = rhs_cast.inject_framing_error;
        inject_noise         = rhs_cast.inject_noise;
        noise_bit_pos        = rhs_cast.noise_bit_pos;
    endfunction

    // -----------------------------------------------------------------------
    // do_compare — equality check on observable fields only
    // inject_* fields are excluded: the scoreboard compares what the DUT
    // received (predicted vs. actual rx_data/parity), not what the driver
    // intended to send.
    // -----------------------------------------------------------------------
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        uart_seq_item rhs_cast;
        if (!$cast(rhs_cast, rhs)) begin
            `uvm_fatal("UART_SEQ_ITEM/CMP", "rhs is not of type uart_seq_item")
            return 1'b0;
        end
        return super.do_compare(rhs, comparer) &&
               (data        === rhs_cast.data)        &&
               (parity_en   === rhs_cast.parity_en)   &&
               (parity_type === rhs_cast.parity_type);
    endfunction

    // -----------------------------------------------------------------------
    // convert2string — used by `uvm_info and waveform annotation
    // -----------------------------------------------------------------------
    function string convert2string();
        return $sformatf(
            "data=0x%02X parity_en=%0b parity_type=%0b inject_framing=%0b inject_noise=%0b noise_pos=%0d",
            data, parity_en, parity_type,
            inject_framing_error, inject_noise, noise_bit_pos);
    endfunction

endclass
