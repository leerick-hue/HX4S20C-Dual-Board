set root [file dirname [file normalize [info script]]]
cd $root
import_device eagle_s20.db -package EG4S20BG256
import_db [file join $root build_attempts seed45_timing_failed diag_pr.db]
clear_sdc
read_sdc [file join $root src timing.sdc]
read_sdc -ip rfifo_32_32_512 [file join $root src afifo_32_16_256.tcl]
update_timing -mode final
report_timing_summary -file [file join $root postroute_reroute before.timing]
report_timing_status -file [file join $root postroute_reroute before.ts]
set_param route post_route_opt high
set_param route postrt_opt_extra_round 4
route
fix_hold -clock_opt
update_timing -mode final
report_area -io_info -file [file join $root postroute_reroute diag_phy.area]
report_timing_summary -file [file join $root postroute_reroute diag_final.timing]
report_timing_status -file [file join $root postroute_reroute diag_phy.ts]
export_db [file join $root postroute_reroute diag_pr.db]
bitgen -bit [file join $root postroute_reroute HDMI_TPG_DIAG.bit]
exit
