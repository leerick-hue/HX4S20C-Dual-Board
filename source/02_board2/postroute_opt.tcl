set root [file dirname [file normalize [info script]]]
cd $root
import_device eagle_s20.db -package EG4S20BG256
import_db [file join $root build_attempts seed45_timing_failed diag_pr.db]
clear_sdc
read_sdc [file join $root src timing.sdc]
read_sdc -ip rfifo_32_32_512 [file join $root src afifo_32_16_256.tcl]
update_timing -mode final
report_timing_summary -file [file join $root postroute before.timing]
report_timing_status -file [file join $root postroute before.ts]
phys_opt -post_route -effort high
fix_hold -clock_opt
update_timing -mode final
report_area -io_info -file [file join $root postroute diag_phy.area]
report_timing_summary -file [file join $root postroute diag_final.timing]
report_timing_status -file [file join $root postroute diag_phy.ts]
export_db [file join $root postroute diag_pr.db]
bitgen -bit [file join $root postroute HDMI_TPG_DIAG.bit]
exit
