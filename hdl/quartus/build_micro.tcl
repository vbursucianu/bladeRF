load_package flow
package require cmdline

set options {\
    { "size.arg" "25" "FPGA Size - 25, 49, or 301" } \
    { "rev.arg" "" "Revision name" } \
    { "stp.arg" "" "SignalTap II File to use" } \
    { "force" "" "Force using SignalTap II" }
}

# Read the revision from the commandline
array set opts [::cmdline::getoptions quartus(args) $options]

proc print_revisions { } {
    project_open -force bladerf -revision base
    puts stderr "Revisions"
    puts stderr "---------"
    foreach $rev [get_project_revisions] {
        if { $rev == "base" } {
            continue
        }
        puts stderr "    $rev"
    }
    project_close
}

# Check to make sure the project exists
if { ![project_exists bladerf] } {
    puts stderr "ERROR: bladeRF project does not exist.  Please run:"
    puts stderr "  $ quartus_sh -t ../bladerf_micro.tcl"
    exit 1
}

# Check to make sure the revison was used on the commandline.
# If it wasn't, print out the revisions available.
if { $opts(rev) == "" } {
    puts stderr "ERROR: Revision required to build\n"
    print_revisions
    exit 1
}

# Check to make sure the revision exists
if { ![revision_exists -project bladerf $opts(rev)] } {
    puts stderr "ERROR: No revision named $opts(rev) in bladeRF project\n"
    print_revisions
    exit 1
}

# Open the project with the specific revision
project_open -revision $opts(rev) bladerf

# Check the size of the FPGA
if { $opts(size) != 301 && $opts(size) != 49 && $opts(size) != 25 } {
    puts stderr "ERROR: Size must be 25, 49, or 301. Size $opts(size) is invalid."
    exit 1
}

# Add signaltap file
set forced_talkback 0
set enable_stp 0
if { $opts(stp) != "" } {
    if { ([get_user_option -name TALKBACK_ENABLED] == off || [get_user_option -name TALKBACK_ENABLED] == "") && $opts(force) } {
        puts "Enabling TalkBack to include SignalTap file"
        set_user_option -name TALKBACK_ENABLED on
        set forced_talkback 1
    }
    # SignalTap requires either TalkBack to be enabled or a non-Web Edition of Quartus (e.g. Standard, Pro)
    if { ([get_user_option -name TALKBACK_ENABLED] == on) || (![string match "*Web Edition*" $quartus(version)]) } {
        puts "Adding SignalTap file: [file normalize $opts(stp)]"
        set_global_assignment -name ENABLE_SIGNALTAP on
        set_global_assignment -name USE_SIGNALTAP_FILE [file normalize $opts(stp)]
        set_global_assignment -name SIGNALTAP_FILE [file normalize $opts(stp)]
        set enable_stp 1
    } else {
        puts stderr "\nERROR: Cannot add $opts(stp) to project without enabling TalkBack."
        puts stderr "         Use -force to enable and add SignalTap to project."
        exit 1
    }
} else {
    set_global_assignment -name ENABLE_SIGNALTAP off
}

set device "5CEB"
if { $opts(size) == 25 } {
    set device "${device}A2"
} elseif { $opts(size) == 49 } {
    set device "${device}A4"
} elseif { $opts(size) == 301 } {
    set device "${device}A9"
}
set device "${device}F23C8"

set_global_assignment -name DEVICE ${device}
set failed 0

# Save all the options
export_assignments
project_close

# The quartus_stp executable creates/edits a Quartus Setting File (.qsf)
# based on the SignalTap II File specified if enabled. It must be run
# successfully before running Analysis & Synthesis.
if { $enable_stp == 1 } {
    if { $failed == 0 && [catch {qexec "quartus_stp --stp_file [file normalize $opts(stp)] --enable bladerf --rev $opts(rev)"} result] } {
        puts "Result: $result"
        puts stderr "ERROR: Adding SignalTap settings to QSF failed."
        set failed 1
    }
}

# Open the project with the specific revision
project_open -revision $opts(rev) bladerf

# Run Analysis and Synthesis
if { $failed == 0 && [catch {execute_module -tool map} result] } {
    puts "Result: $result"
    puts stderr "ERROR: Analysis & Synthesis Failed"
    set failed 1
}

# Run Fitter
if { $failed == 0 && [catch {execute_module -tool fit} result ] } {
    puts "Result: $result"
    puts stderr "ERROR: Fitter failed"
    set failed 1
}

# Run Static Timing Analysis
if { $failed == 0 && [catch {execute_module -tool sta} result] } {
    puts "Result: $result"
    puts stderr "ERROR: Timing Analysis Failed!"
    set failed 1
}

# Run Assembler
if { $failed == 0 && [catch {execute_module -tool asm} result] } {
    puts "Result: $result"
    puts stderr "ERROR: Assembler Failed!"
    set failed 1
}

# Run EDA Output
#if { $failed == 0 && [catch {execute_module -tool eda} result] } {
#    puts "Result: $result"
#    puts stderr "ERROR: EDA failed!"
#    set failed 1
#} elseif { $failed == 0 } {
#    puts "INFO: EDA OK!"
#}

# If we were forced to turn on TALKBACK .. turn it back off
if { $forced_talkback == 1 } {
    puts "Disabling TalkBack back to original state"
    set_user_option -name TALKBACK_ENABLED off
}

project_close

