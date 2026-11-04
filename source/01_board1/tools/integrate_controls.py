"""Apply reviewed control-only changes to the hardware-accepted HD photo base."""
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
STABLE=ROOT.parent/'phone_ir_fit_link_ack_20261030'
EXT=Path('src/user_source/hdl_source/extensions')
for name in ('board_remote_control.v','event_packet_rx.v','event_packet_tx.v','uart_tx.v'):
    shutil.copy2(STABLE/EXT/name,ROOT/EXT/name)
shutil.copy2(STABLE/EXT.parent/'board_video_controls.v',ROOT/EXT.parent/'board_video_controls.v')

top=ROOT/'src/user_source/hdl_source/top_tf_hdmi_audio.v'
s=top.read_text(encoding='utf8')
def change(old,new):
    global s
    assert s.count(old)==1,(old,s.count(old))
    s=s.replace(old,new)
change('    output [5:0]                seg_sel,','    output                      link_ack_tx, // G11: delivery ACK to Board2\n    output [5:0]                seg_sel,')
change('.ir_in(1\'b1)', '.ir_in(ir_in)')
change('board_remote_control #(.CLK_HZ(40000000)) remote',
       'wire [7:0] remote_bytes,remote_packets;\nwire ack_valid,ack_ready,ack_byte_valid,ack_byte_ready;\nwire [31:0] ack_data;wire [7:0] ack_sequence,ack_byte;\nboard_remote_control #(.CLK_HZ(40000000),.ACK_ENABLE(1)) remote')
change('.link_rx(1\'b1)', '.link_rx(link_rx)')
change('    .unsupported_count(remote_unsupported),.packet_error_count(remote_errors));',
'''    .unsupported_count(remote_unsupported),.packet_error_count(remote_errors),
    .received_byte_count(remote_bytes),.valid_packet_count(remote_packets),
    .ack_valid(ack_valid),.ack_ready(ack_ready),.ack_data(ack_data),.ack_sequence(ack_sequence));
event_packet_tx #(.USE_EVENT_SEQUENCE(1)) acknowledgements(.clk(decode_clk),.rst_n(media_decode_rst_n),
    .event_valid(ack_valid),.event_ready(ack_ready),.event_data(ack_data),.event_sequence(ack_sequence),
    .byte_valid(ack_byte_valid),.byte_ready(ack_byte_ready),.byte_data(ack_byte));
uart_tx #(.CLK_HZ(40000000),.BAUD(115200)) acknowledgement_wire(.clk(decode_clk),.rst_n(media_decode_rst_n),
    .byte_valid(ack_byte_valid),.byte_ready(ack_byte_ready),.byte_data(ack_byte),.tx(link_ack_tx),.busy());''')
change('key_press_debounce #(.CLK_FREQ_HZ(50000000)) probe_key(.clk(clk),.rst(!rst_n),.button_in(key1),.press_pulse(photo_probe_next));',
       "// KEY1 is restored to album navigation; hold the observer on its default page.\nassign photo_probe_next=1'b0;")
change("    .key_n(3'b111),.command_valid(1'b0)", '    .key_n({key3,key2,key1}),.command_valid(ctl_valid)')
change('.bars_enable(bars_enable),.music_play(music_play),.want_video(want_video));',
       ".bars_enable(bars_enable),.music_play(music_play));\n// This release prioritizes native HD photos and keeps the proven photo controls.\nassign want_video=1'b0;")
change(".play_enable(player_play[1]),.key1(1'b1),.key2(1'b1)", '.play_enable(player_play[1]),.key1(key1),.key2(key2)')
change(" .photo_next_cmd(1'b0),.photo_auto_valid_cmd(1'b0),.photo_auto_enable_cmd(1'b0)",
       ' .photo_next_cmd(photo_next_cmd),.photo_auto_valid_cmd(photo_auto_valid_cmd),.photo_auto_enable_cmd(photo_auto_enable_cmd)')
top.write_text(s,encoding='utf8')

bmp=ROOT/'src/user_source/hdl_source/SD/sd_card_bmp.v'
s=bmp.read_text(encoding='utf8');assert s.count('.KEEP_ASPECT(0)')==1
bmp.write_text(s.replace('.KEEP_ASPECT(0)','.KEEP_ASPECT(1)'),encoding='utf8')

project=ROOT/'src/td_project/HX4S20C_Extensions.al'
s=project.read_text(encoding='utf8')
anchor='            <File Path="../user_source/hdl_source/extensions/event_packet_rx.v">'
assert s.count(anchor)==1
entries=''
for i,name in enumerate(('event_packet_tx.v','uart_tx.v')):
    entries+=f'''            <File Path="../user_source/hdl_source/extensions/{name}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{501+i}"/>
                </FileInfo>
            </File>
'''
project.write_text(s.replace(anchor,entries+anchor),encoding='utf8')

pin=ROOT/'src/user_source/constraints_source/pin.adc'
with pin.open('a',encoding='utf8') as f:
    f.write('\nset_pin_assignment {link_ack_tx} {LOCATION = G11; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 4; PULLTYPE = NONE;}\n')
sdc=ROOT/'src/user_source/constraints_source/timing.sdc'
with sdc.open('a',encoding='utf8') as f:
    f.write('''
# Restored IR/UART control mailboxes: first toggle samplers only. Payloads
# remain held through the handshake and retain a bounded flight time.
set_false_path -to [get_regs {infrared/mailbox/ack_meta infrared/mailbox/req_meta commands/keyboard_mailbox/ack_meta commands/keyboard_mailbox/req_meta}]
set_max_delay -datapath_only -from [get_regs {infrared/mailbox/payload[*]}] -to [get_regs {infrared/mailbox/dst_payload[*]}] 9.5
set_max_delay -datapath_only -from [get_regs {commands/keyboard_mailbox/payload[*]}] -to [get_regs {commands/keyboard_mailbox/dst_payload[*]}] 9.5
# UART serializer launches in the actual 40 MHz decode clock domain.
set_output_delay -clock [get_clocks {jpeg_clk}] 0 [get_ports {link_ack_tx}]
''')
print('Integrated photo controls, phone IR, UART delivery ACK, and aspect fit.')
