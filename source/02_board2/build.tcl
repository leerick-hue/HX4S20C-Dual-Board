set root [file dirname [file normalize [info script]]]
cd [file join $root project]
import_device eagle_s20.db -package EG4S20BG256
open_project -single_run [file join $root project HX4S20C_Extensions.al]
elaborate -top top
cd $root
set_param place effort high
set_param place seed 45
set_param route post_route_opt high
read_adc [file join $root src pin.adc]
set_param rtl min_ripple_len 12
set_param rtl resource_sharing auto
set_param rtl shifter_style shifter_reg
optimize_rtl
read_sdc [file join $root src timing.sdc]
read_sdc -ip rfifo_32_32_512 [file join $root src afifo_32_16_256.tcl]
set_param gate add_map_lut_struct high
set_param gate map_mode area_prior
set_param gate multi_thread_mapping partition
optimize_gate
legalize_phy_inst
report_area -file diag_gate.area
place
route
update_timing -mode final
fix_hold -clock_opt
update_timing -mode final
report_area -io_info -file diag_phy.area
report_timing_summary -file diag_final.timing
report_timing_status -file diag_phy.ts
export_db diag_pr.db
bitgen -bit HDMI_TPG_DIAG.bit
close_project
exit
