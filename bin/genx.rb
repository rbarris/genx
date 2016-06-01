#!/usr/bin/env ruby

###############################################################################
# requires
require 'csv'
require 'getoptlong'
require 'pathname'

###############################################################################

# key globals

# XPR path (Pathname object)
# points to XPR project being targeted (--xpr_file argument)
# global var: $g_xpr_file_path ###_EXT_### path to Vivado XPR project file
$g_xpr_file_path = nil

# Path to the generated source directory.  Defaults to <xpr-project-name> + "_gen", but can be forced with --gen_dir
# script ensures it is set to something before first job begins processing
$g_gen_dir_path = nil

# debug modes
$debugmode = 0
$axidebug = 0

###############################################################################

# genx functions by pulling in 'jobs' - chunks of Ruby code  - and executing
# them (via 'eval').

# those jobs can use some functions and variables contained in the script - 
# those are labeled with the marker _EXT_ (incl three leading and trailing
# pound signs) to make it more clear.

###############################################################################

# helper functions for indentation

# http://stackoverflow.com/questions/8889870/ruby-regex-to-match-tabs-and-replace-with-2-spaces
# This algorithm by Brian Candler (B.Candler@pobox.com) found on the
# org.ruby-lang.ruby-talk mailing list
# http://markmail.org/message/avdjw34ahxi447qk
# Date: 2003-5-31 13:35:09
# Subject: Re: expandtabs

def expand_tabs(s, tabsize = 4)
  s.gsub(/([^\t\n]*)\t/) do
    $1 + " " * (tabsize - ($1.size % tabsize))
  end
end

# count padding on left side of a string (tabs or spaces)
def count_leading_whitespace( str, tabsize = 2 )
	temp = expand_tabs(str,tabsize)

	spaces = 0	
	idx = 0
	while( idx < temp.size ) do
		if (temp[idx]==' ')
			spaces += 1
		else
			# hit non white space
			return spaces
		end
		idx += 1
	end
	return spaces # could happen if it was all spaces
end

def indented_replace( text, marker, repl, tabsize = 2 )
	# where "marker" appears, replace it with an indented version of "repl"
	# so figure out how-much-indentation "marker" has first,
	# then inject that much whitespace before each line of "repl" (except the first!)
	
	textcopy = text.dup;
	
	# find first un-replaced marker and replace it at proper indentation level
	textcopy.each_line do |line|
		if (line.include?( marker )) then		 # marker
			# figure out how indented it is
			space_count = count_leading_whitespace( line, tabsize )
			
			# replace all the newlines in the replacement text by newline and then N spaces.
			repl_indented = repl.gsub("\n", "\n" + (" " * space_count) )

			# trim off leading or trailing newlines / whitespace
			repl_indented.strip!
			
			# drop the replacement text in
			# this assume there's only one usage of a marker, so we don't need to figure indentation on each one
			textcopy.gsub!( marker, repl_indented )

			# done
			return textcopy
  	end
	end
	return textcopy
end

###############################################################################

# find file pathname (for opening to read)
def find_file( str )
	temp = Pathname.new( str )

	# if absolute, done

	temp = Pathname.new( str )
	if (temp.absolute?)
		return temp
	end
		
	# try in cwd
	
	wd = Pathname.getwd
	temp = wd.join( temp )
	if (temp.exist? and temp.file?)
		return temp
	end
	
	temp = Pathname.new( File.dirname(__FILE__) ).join( "../lib/#{str}" )
	if (temp.exist? && temp.file?)
		return temp
	end

	printf("\n ** find_file: filename %s not found\n",str )
	abort "stopping"
		
	return nil
end

###############################################################################
###############################################################################
###############################################################################

# tracking the location of the Vivado project (.xpr) and the choice of generated output dir

def set_xpr_file_path( str )
	xpr_file_path = Pathname.new( str )
	if (! xpr_file_path.absolute?)
		wd = Pathname.getwd
		xpr_file_path = wd.join( xpr_file_path )
	end

	# it must be an XPR file
	if (xpr_file_path.exist? && xpr_file_path.file?)
		# likely success, check file suffix
		if ( xpr_file_path.basename.to_s.end_with?(".xpr") || xpr_file_path.basename.end_with?(".XPR") ) 
			# success
			$g_xpr_file_path = xpr_file_path
		else
			printf("\n ** set_xpr_file_path: path %s is not an XPR file\n",str )
			abort "stopping"
		end
	else
		printf("\n ** set_xpr_file_path: path %s is no good\n",str )
		abort "stopping"
	end
end

def check_gen_dir_path
	# return false if it still needs to be created and assigned.
	if (! $g_gen_dir_path)
		return false
	end
	
	if (! $g_gen_dir_path.exist?)
		return false
	end
	
	if (! $g_gen_dir_path.writable?)
		return false
	end
	
	return true
end

def set_gen_dir_path( str )
	if (str.size!=0)
		# user supplied a pathname for the generation dir
		$g_gen_dir_path = Pathname.new( str )
		if (! $g_gen_dir_path.absolute?)
			wd = Pathname.getwd
			$g_gen_dir_path = wd.join( $g_gen_dir_path )
		end
	else
		# (caller passed "")
		# user never supplied a generation dest dir, auto select one
		
		# used to extend the project basename so proj2.xpr -> proj2_gen/
		# but that got really repetitive to type.  Back to just using "gen" for the output default folder name.
		if (1)
			gen_dir_name = "gen"
		else
			# use the base name of the XPR file as a basis, so test1.xpr --> test1_gen
			gen_dir_name = $g_xpr_file_path.basename.to_s
			gen_dir_name.gsub!(".xpr","")
			gen_dir_name.gsub!(".XPR","")
			gen_dir_name += "_gen";
		end

		$g_gen_dir_path = $g_xpr_file_path.parent.join(gen_dir_name);
	end

	# either way, try to make a dir
	if (! $g_gen_dir_path.exist? )
		$g_gen_dir_path.mkdir
	end
	
	# verify the gen dir is there
	if (! check_gen_dir_path )
		printf("\n ** set_gen_dir_path: (1) could not find or create generation directory %s\n",$g_gen_dir_path.to_s )
		abort "stopping"
	end
end

def write_generated_file(filename, text) ###_EXT_### write text to a file in generated output directory.	
	# figure path to the new file, and write it
	filepath = $g_gen_dir_path.join(filename)	
	File.write( filepath.cleanpath, text )
	printf( "\n   wrote file: %s", filepath.basename.to_s )
end

###############################################################################
###############################################################################
###############################################################################
# input source file list

# each .v file may contain N jobs
# jobs get processed in order
# defines passed to genx on command line are visible during all processing

# defines in `includes inside these files are not visible / known to script
# (because script doesn't do `include processing)

# list of files to process (Pathname objects)
$g_source_pathnames = []

def add_source_pathname( str )
	temp_path = Pathname.new( str )
	if (! temp_path.absolute?)
		wd = Pathname.getwd
		temp_path = wd.join( temp_path )
	end
	
	if (temp_path.exist? && temp_path.file?)
		# success	
		($g_source_pathnames ||= []).push(temp_path)
	else
		printf("\n ** add_source_pathname: path %s is no good\n",str )
		abort "stopping"
	end
end

###############################################################################
###############################################################################
###############################################################################
# global defines
# job code can add defines by calling "add_define"
# and it can test for defines (in later steps) by calling "is_defined".
# defines can get set up in an early job and tested in a later job.
# the define collection can be written out using "write_defines_verilog"

$g_defines = Hash.new
$g_defines_checkpoint = Hash.new

def checkpoint_defines
	# used to save off state of define table after CLI args have been absorbed.
	# so if we process more than one file that each add some defines, they won't all pile up
	$g_defines_checkpoint = $g_defines.dup
end

def restore_defines_from_checkpoint
	$g_defines = $g_defines_checkpoint.dup
	# rewind state of define table to only what the CLI args provided.
end

def is_defined( str ) ###_EXT_### test whether a particular symbol has been defined
	result = ($g_defines[str] != nil)
	return result
end

def get_define_value( str ) ###_EXT_### return the value to which a define was set
	# return -1 if not defined.
	if (is_defined(str))
		result = $g_defines[str]
	else
		result = -1
	end
	return result
end

# call one of these from within a job to add a defined symbol to the global define table.
def add_define( str ) ###_EXT_### add a defined symbol
	$g_defines[ str ] = 1
end

def add_define_value( str, val ) ###_EXT_### add a symbol defined to a specific value
	$g_defines[ str ] = val
end

def write_defines_verilog( vhname )			###_EXT_### emit the Verilog source representing all the defines that are set
	defines_text = ""
	
	# walk the define table
	# pass through the value, even if conditionalized code can only react to defined-or-not
	$g_defines.each {|key, value| defines_text += "`define #{key} #{value}\n" }
		
	write_generated_file( vhname, defines_text )
end

def write_defines_c( chname )			###_EXT_### emit C source representing all the defines that are set
	defines_text = ""
	
	# walk the define table
	# pass through the value, even if conditionalized code can only react to defined-or-not
	$g_defines.each {|key, value| defines_text += "#define #{key} #{value}\n" }
		
	write_generated_file( chname, defines_text )
end

###############################################################################
###############################################################################
###############################################################################
# ROM/LUT generation
# function to populate and return an array of float values over appropriate range
# main need is for function tables in fixed point format
# separate the code for generation of numeric values in -1.0 - 1.0 range from the writing of MIF file hex data

# standard form for a plugin function looks like
# def my_function( idx, lim ) -> return a float value in -1.0...1.0 range, limit typ power of two

###############################################################################
# pre baked functions

def theta_twopi(idx,lim) ###_EXT_### convert a phase angle from (index,range) to a 0-2*pi number.
	theta = (idx * 2.0 * Math::PI) / lim
	return theta
end

def sinewave(idx,lim) ###_EXT_### sine function.  Arguments must be named idx and lim
	result = Math::sin(theta_twopi(idx,lim))
	return result
end

def squarewave(idx,lim) ###_EXT_### square wave function.
	result = (idx >= lim/2)? 1.0 : -1.0
	return result
end

def trianglewave(idx,lim) ###_EXT_### triangle wave function.
	uphase = (idx*1.0) / (lim*1.0)	# convert idx to 0-1 domain
	result = (uphase <0.25)?(uphase *4.0):((uphase<0.75)?(2.0-(uphase*4.0)):(uphase*4.0-4.0));
	return result
end

def whitenoise(idx,lim) ###_EXT_### white noise function
	result = ((rand * 2.0) - 1.0);
	return result
end

def generate_function_values(function, lim)	###_EXT_### generates an array of values based on a supplied function and count (lim)
	values = Array.new(lim, 0.0)

	idx = 0
	while (idx < lim) do
		value = eval( function )
		values[idx] = value				
		idx = idx+1
	end

	return values	
end

def write_fixedpoint_mif(values, bitwidth, mifname) ###_EXT_### function to convert an array of (-1...+1) floats into 2^n fixed point hex and write it out to a MIF

	mif_text = ""
	idx = 0
	while (idx < values.count) do		

		value = values[idx]
		
		# clamp between -0.9999 and 0.9999 to avoid madness
		if (value >0.99999)
			value = 0.99999
		end
		if (value <-0.99999)
			value = -0.99999
		end

		# binary value (fixed point scaling applied)
		bvalue = value * (2.0 ** (bitwidth-1))
		
		# binary to hex.  Ruby may prepend extra unwanted chars if negative, so clean it up after
		bstring = sprintf( "%08X", bvalue );
	
		# calc actual byte count for ROM
		bytecount = bitwidth/8
			
		# pick off last (bitwidth/4) characters generated
		bstring = bstring.reverse[0...(bytecount*2)].reverse
		
		if ($debugmode!=0)
			printf("%d/%d --> %7.4f (signed hex: %s) \n", idx, values.count, value, bstring )
		end
		
		# emit MIF file hex (one byte, one space, repeat)
		byteindex = 0
		while (byteindex < bytecount) do
			mif_text += sprintf("%2s%s", bstring[byteindex*2...(byteindex*2+2)], byteindex < (bytecount-1) ? "" : "\n" );
			byteindex = byteindex+1
		end
		
		idx = idx+1
	end

	write_generated_file(mifname, mif_text)
end

# string template for generating ROM decls
$g_moduletemplate = <<-EOF
module LABEL_ADDRCOUNTxDATAWIDTH_rom (	input [ADDRWIDTH_LESS1:0]	addr,	output [DATAWIDTH_LESS1:0] data );
reg [DATAWIDTH_LESS1:0] rom[0:ADDRCOUNT_LESS1];
initial begin  $readmemh("MIFNAME", rom, 0, ADDRCOUNT_LESS1);  end
assign data = rom[addr];
endmodule
EOF

def generate_rom_decl(label, acount, awidth, dwidth, function, mifname)
	moduletext = $g_moduletemplate.dup
	moduletext.gsub!("LABEL",label.to_s)
	
	moduletext.gsub!("ADDRCOUNT_LESS1",(acount-1).to_s)
	moduletext.gsub!("ADDRCOUNT",acount.to_s)
	
	moduletext.gsub!("ADDRWIDTH_LESS1",(awidth-1).to_s)
	moduletext.gsub!("ADDRWIDTH",awidth.to_s)
	
	moduletext.gsub!("DATAWIDTH_LESS1",(dwidth-1).to_s)
	moduletext.gsub!("DATAWIDTH",dwidth.to_s)
	
	moduletext.gsub!("MIFNAME",mifname)
	return moduletext
end


def multi_generate_lut(label, function, datawidths, addrwidths)	###_EXT_### main function to generate multiple LUTs based on a function
	# label: arbitrary text prefix to name the table with. (starting with 'x/y/z' will keep it down in the vivado source list)
	#		example: "xsine" -> will lead to MIF filename like "xsine_256x8.mif"
	# function: function to pass through to generate_function_values.
	#		example: "squarewave(idx,lim)"
	#	datawidths and addrwidths are arrays of bit width values.
	#		datawidth should be 8, 16 or 32
	#		addrwidth should be in 4-11 range (yielding ROM of 16-2048 entries)

	multi_decl_text = ""				# accumulate ROM decls for this batch to return to caller
	
	for dwidth in datawidths do

		if ((dwidth!=8) && (dwidth!=16) && (dwidth!=32))
			printf("\n ** multi_generate_lut: data width %d is no good\n",dwidth )
			abort "stopping"
		end
		
		for awidth in addrwidths do
			# validate width
			if ((awidth<2) || (awidth>16))
				printf("\n ** multi_generate_lut: addr width %d is no good\n",awidth )
				abort "stopping"
			end
			
			# figure out the base name for the MIF file aka "xsine_256x8.mif"
			acount = 2**awidth
			mifname = sprintf("%s_%dx%d.mif", label, acount, dwidth )
			
			# generate values
			value_array = generate_function_values(function,acount)
			
			# emit MIF
			write_fixedpoint_mif(value_array,dwidth,mifname)
			
			# generate verilog module decl wrapping that data
			decl_text = generate_rom_decl(label, acount, awidth, dwidth, function, mifname)

			decl_text = sprintf("\n// -------------------------------- %s\n%s",mifname,decl_text)
			
			# some logging
			if ($debugmode != 0)
				printf(decl_text)
			end
			
			# accumulate decl into batch
			multi_decl_text += decl_text
		end
	end
	return multi_decl_text # The MIF files went to disk already.  This text has the Verilog module wrappers that references those MIF files.  Caller needs to write it out.
end


###############################################################################
###############################################################################
###############################################################################
# AXI glue generation
# collect a list of register definitions from the job, emit a .vh file with ready made AXI glue

# functions needed
# begin glue setup (init reg defs array)
# set the offset cursor (auto incrementing) - allowed to be sparse
# add a register (presently fixed at 32-bit to keep it simple)
#		register info: name, mode( passive, readthrough, writethrough ), comment
#
#			"passive" mode:
#				just like original Xilinx generated glue
#				child logic can observe value but can't change it - just reference 'myreg'
#				AXI master can read or write the value.
#				no read/write signalling is provided to child logic.
#
#			readthrough mode: two new wires created
#				myreg -> myreg_rddata: 	wires from which the register is continuously refreshed.
#				myreg -> myreg_rdtick:	wire signals a read pulse to child logic (i.e. "advance value")
#				AXI master can only read the value.  Writing is a no-op
#				Author must provide connections to the extra wires to supply current value continuously, and react to the intake tick.
#
#			writethrough mode: one new wire created (actually a reg)
#				myreg -> myreg_wrtick: wire signals that the value has changed (rises for one cycle after data arrives)
#					delaying it one tick -> child logic does not have to think about byte enables.
#				AXI master can read or write the value.
#				Author must monitor myreg_wrtick and capture new value.
#
# generate finished AXI glue text
# generate matching C header for offsets
# future: include some defines for register bit fields

# define a struct for tracking register definitions
SRegDef = Struct.new(:name, :byteoffset, :mode, :comment) do
  def to_ary
    [name, byteoffset, mode, comment]
  end
end

$g_reg_defs = nil
$g_reg_offset = 0
$g_max_offset = 16;	# one past last byte.  16 bytes of addr decode created even if only one register.

	
def next_powerof2(val)	# return a power of two which is >= the value provided. aka 2^(ceil(log2(val)))
	result = 1
	while( result < val) do
		result *= 2;
	end
	return result
end

def axi_start ###_EXT_###  start up an AXI register bank configuration
	$g_reg_defs = Array.new
	$g_reg_offset = 0
end

def axi_set_reg_offset( offset ) ###_EXT_###  set the offset cursor that will apply to the next register added
	# validate offset, somewhat arbitrary rules here
	if ( (offset<0) || (offset > 65536) || ((offset % 4)!=0) )
		printf("\n ** axi_glue_set_offset: reg offset %d is no good\n",offset )
		abort "stopping"
	else
		$g_reg_offset = offset
	end
end

def axi_add_reg( rname, rmode="passive", rcomment="" ) ###_EXT_### add one register to the set.  Offset is auto incremented by 4.
	rbyteoffset = $g_reg_offset
	
	# verify that no prior register added has the same offset
	$g_reg_defs.each_with_index do |regdef,index|
		if (regdef.byteoffset == rbyteoffset)
			printf("\n ** axi_add_reg: new reg %s offset %d conflicts with reg %s\n",rname,rbyteoffset,regdef.name )
			abort "stopping"
		end

		if (regdef.name == rname)
			printf("\n ** axi_add_reg: reg name %s used more than once\n",rname )
			abort "stopping"
		end
	end
	
	#add the def to the pile
	$g_reg_defs << SRegDef.new( rname, rbyteoffset, rmode, rcomment )
	
	#raise max offset if needed (need this to calculate the address decoding width for the glue)
	if ((rbyteoffset+4) > $g_max_offset)
		$g_max_offset = rbyteoffset+4
	end
	
	#autoinc for the next one
	axi_set_reg_offset( rbyteoffset + 4 )
end

def axi_gen_text( text ) ###_EXT_### emit the finished text of the generated AXI glue for the register set.
	# emit glue text: params, ports, logic.
	# 'text' starts out as the base glue file and then gets mutated and returned
	
	# set databus width
	data_bit_width = 32
	
	# first calculate how wide the address bus needs to be and how many decode bits from that.
	# if $g_max_offset is not a power of two, raise it to next power of two
	
	last_byte_offset = $g_max_offset - 1;										# highest addressable byte
	last_byte_nextpow2 = next_powerof2( last_byte_offset )	# find next higher power of two than that offset
	addr_binary_mask = (last_byte_nextpow2-1).to_s(2)				# subtract one from that power to get an address mask of all 1's
	addr_bit_width = 	addr_binary_mask.size									# count the 1's, that is the address bus width (byte addressing)
	
	# address decode width is address width minus log2(datapath_byte_width aka (data_bit_width/8) )
	# presently hardwired to 2..
	addr_decode_width = addr_bit_width - 2
	
	# genx generated glue has zero adjustable parameters, just direct substitution of values into the text.
	# addresses the C_S_AXI_* problem where Vivado latches stale values at the time of adding HDL to BD...
	# which would in turn cause synthesis failures later if you added registers and increased address width.
	
	text.gsub!("X_AXI_DATA_WIDTH_X","#{data_bit_width}")
	text.gsub!("X_AXI_ADDR_WIDTH_X","#{addr_bit_width}")
	text.gsub!("X_AXI_OPT_MEM_ADDR_BITS_X","#{addr_decode_width}")
	

	################################################ reg instances

	# replace	X_GLUE_REGISTER_INSTANCES_X with N register decls "reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0"
		# a reg instance may also bring along wires / regs for readthrough / writethrough support.
		# can also include assign statements that will drive readthrough tick wires	
	reg_instances_text = ""

	
	################################################ write-handling and readthrough
	
	# replace X_GLUE_REGISTER_RESETS_X with N reg resets to zero. 
		# must also include resets of all writethrough tick regs.
	reg_resets_text = ""

	# replace X_GLUE_REGISTER_CLEAR_WRTICKS_X clearing of all writethrough tick regs (yes, again)
	reg_clear_wrticks_text = ""
		
	# replace X_GLUE_REGISTER_WRITECASES_X with N write handling cases by reg index-not-offset
		# ** must omit cases for any readthrough registers, they are sourced below **
	# example
	#	10'h0: begin
	#	  for ( byte_index = 0; byte_index <= (#{data_bit_width}/8)-1; byte_index = byte_index+1 )
	#	    if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	#	      slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	#	    end  
	# end
	reg_writecases_text = ""

	# replace X_GLUE_REGISTER_READTHROUGHS_X with assignments into any readthrough registers
	# example
	# systicks <= systicks_rddata;	
	reg_readthroughs_text = ""
	
	################################################ read-handling related
	

	# replace X_GLUE_REGISTER_READCASES_X with N read handling cases by reg index (example)
	# don't forget to put the right bit width on the index, i.e. address width minus two for 32b regs 
	#	2h0   : reg_data_out <= slv_reg0;
	reg_readcases_text = ""
	
	####### iterate over the regs supplied by the input script
	
	$g_reg_defs.each_with_index do |regdef, index|
		if ($debugmode != 0) then
			printf( "\nProcessing register name '%s'",regdef.name );
		end
	
		########################################## instance stuff		
		#instance the reg
		reg_instances_text << sprintf( "reg [#{data_bit_width}-1:0] %s;\n", regdef.name );
		
		# instance wires if mode is readthrough or writethrough
		if (regdef.mode == "readthrough")
			# add a wire for the read data - user logic must assign it from a continuous value source
			reg_instances_text << "\twire [#{data_bit_width}-1:0] #{regdef.name}_rddata;\n"

			# add a wire for the read tick - user logic may observe it if needed to advance value
			reg_instances_text << "\twire #{regdef.name}_rdtick;\n"
			reg_instances_text << sprintf("\tassign #{regdef.name}_rdtick = slv_reg_rden && (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS-1:ADDR_LSB]==%d);\n", regdef.byteoffset/4 )
		end

		########################################## write stuff (incl reset and readthrough)
		# reset
		if ($axidebug != 0)
			reg_resets_text << "#{regdef.name} <= 32'd#{regdef.byteoffset};\n"		# reset regs in axi debug mode, to their offset
		else
			reg_resets_text << "#{regdef.name} <= 0;\n"
		end

		# writethrough stuff
		if (regdef.mode == "writethrough")
			# add a reg for the write tick - user logic is notified that value in reg has been updated
			reg_instances_text << "\treg #{regdef.name}_wrtick;\n"

			# add a reset for that reg
			reg_resets_text << "#{regdef.name}_wrtick <= 0;\n"		
						
			# add a write tick clear step
			reg_clear_wrticks_text << "#{regdef.name}_wrtick <= 0;\n"
		end

		# emit write handling if the reg can be written (aka not readthrough)
		if (regdef.mode != "readthrough")

			reg_writecases_text += sprintf( "%d'h%x:\t\t\t// #{regdef.name}\n", addr_decode_width, regdef.byteoffset/4 )
			reg_writecases_text += sprintf( "begin\n" )
			
			reg_writecases_text += sprintf( "\tfor ( byte_index=0; byte_index <= (#{data_bit_width}/8)-1; byte_index = byte_index+1 )\n" )
			reg_writecases_text += sprintf( "\t\tif ( S_AXI_WSTRB[byte_index] == 1 ) begin\n")
			reg_writecases_text += sprintf( "\t\t\t%s[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];\n", regdef.name )
			if (regdef.mode == "writethrough")
				# add a line that will mark the write tick reg for this register on this cycle
				reg_writecases_text << "\t\t\t#{regdef.name}_wrtick <= 1;\n"
			end		
			reg_writecases_text += sprintf( "\tend\n" )
			reg_writecases_text += sprintf( "end\n\n" )
		else
			# must add readthrough assignment for this reg (this gets put in the write handling always-block)
			reg_readthroughs_text << "#{regdef.name} <=  #{regdef.name}_rddata;\n"
		end

		########################################## read stuff
		# read case
		reg_readcases_text += sprintf( "%d'h%x: reg_data_out <= %s;\n", addr_decode_width, regdef.byteoffset/4, regdef.name )

		# little whitespace		
		reg_instances_text << "\n"

	end	# end reg loop

	############################################ one-offs	
	# add default handling to write cases. walk the reg list again to find those.
	reg_writecases_text += sprintf( "default:\nbegin\n" )
	$g_reg_defs.each_with_index do |regdef, index|
		# do not emit a write case for regs which cannot be written, as that will yield multiple-drivers and not compile
		if (regdef.mode != "readthrough")
			reg_writecases_text += sprintf( "\t%s <= %s;\n", regdef.name, regdef.name )
		else
			reg_writecases_text += sprintf( "\t// register %s cannot be written because it is readthrough\n", regdef.name )
		end
	end
	reg_writecases_text += sprintf( "end\n" )

	# add default handling for read cases (just return 0)
	reg_readcases_text += sprintf( "default: reg_data_out <= 0; \n" )
	
	
	# place generated text blobs into the resulting text

	## instances	
	text = indented_replace( text, "X_GLUE_REGISTER_INSTANCES_X", reg_instances_text)
	
	## write side
	text = indented_replace( text, "X_GLUE_REGISTER_RESETS_X",reg_resets_text)
	text = indented_replace( text, "X_GLUE_REGISTER_CLEAR_WRTICKS_X",reg_clear_wrticks_text)	
	text = indented_replace( text, "X_GLUE_REGISTER_WRITECASES_X",reg_writecases_text)
	text = indented_replace( text, "X_GLUE_REGISTER_READTHROUGHS_X", reg_readthroughs_text)

	## read side
	text = indented_replace( text, "X_GLUE_REGISTER_READCASES_X",reg_readcases_text)				
	
	return text
end



def axi_write_verilog( basegluename, gluename ) ###_EXT_### main function for generating AXI register glue. baseglue name refers to a file in genx's lib folder.
	baseglue = find_file( basegluename )
	if (baseglue!=nil)
		axi_text = ""
		
		# prepend a list of the regs / offsets / comments
		$g_reg_defs.each_with_index do |regdef,index|
			axi_text += sprintf("// reg: %-20s  offset 0x%04x  mode: %-20s    %s \n",regdef.name,regdef.byteoffset,regdef.mode,regdef.comment )
		end
	
		# tack on the base glue text
		axi_text += File.read( baseglue )
		
		# generate the finished glue text
		axi_text = axi_gen_text( axi_text )
		
		# ship it out
		write_generated_file(gluename, axi_text)		
	end	
end

def axi_write_c_header( structname, headername ) ###_EXT_### function for generating C header with register offset information
	
	# copy the reg defs
	regdefs = $g_reg_defs
	
	# sort by ascending offset
	regdefs.sort! {|left, right| left.byteoffset <=> right.byteoffset}	

	# track offset of first byte not written so far
	# purpose - to detect need for padding, and how much.
	# (registers can be sparsely arranged)
	unwritten_offset = 0;

	hdr_text = ""
	hdr_text += sprintf("// structure declaration for module %s \n",structname )
	hdr_text += sprintf("typedef struct\n{\n" )
	
	regdefs.each_with_index do |regdef,index|
		# check if padding from previous offset is needed
		if (regdef.byteoffset > unwritten_offset)
			# how much pad...
			pad_words = (regdef.byteoffset - unwritten_offset) / 4;
			hdr_text += sprintf("\t/* offset 0x%04x */\tunsigned long\t\t\t_pad_0x%04x[%d];\n", unwritten_offset, unwritten_offset, pad_words )
		end
		
		#emit reg
		regnametext = "#{regdef.name};"	# incl semicolon so it gets aligned along with text of name
		hdr_text += sprintf("\t/* offset 0x%04x */\tunsigned long\t%-40s\t//%-60s\n", regdef.byteoffset, regnametext, regdef.comment  )

		# track written offset
		unwritten_offset = regdef.byteoffset+4;		
	end

	# no munging the struct name, pass it through as-is
	hdr_text += sprintf("} %s;\n\n", structname )

	# ship it out
	write_generated_file(headername, hdr_text)		
end


###############################################################################
###############################################################################
###############################################################################
# XDC constraint file generation

# xdc_start						method to start XDC setup - supply the names of the chip table and board table (currently CSV based)
# xdc_set_iostandard	method to set the current IOSTANDARD (typ LVCMOS33) - it sticks for the pins added following
# xdc_add_pin					method to add a pin connection (needs signal name, and physical connector pin name i.e. JA_P11)
# xdc_generate_text		method to map all the pins to device signals (i.e. YY11) and generate the XDC text
# xdc_write_xdc				ship result to xdc file in gen folder

# see http://stackoverflow.com/questions/3717464/ruby-parse-csv-file-with-header-fields-as-attributes-for-each-row
# see http://andrew.coffee/blog/skipping-blank-lines-in-ruby-csv-parsing.html (how to use :match)

$g_xdc_chiptable = nil
$g_xdc_boardtable = nil

$g_xdc_iostandard = "LVCMOS33"

$g_xdc_text = ""

# this is good enough to skip blank lines and ignore any line that starts with some
# whitespace and a hash character.  Some silliness may ensue if CSV rows have trailing
# comments on the right..

$csv_options = { :headers => true, :header_converters => :symbol, :skip_blanks => true, :skip_lines => /^(\s*)#/ }

# chiptable - path to CSV describing chip pads
#	Required columns 'chip_pad', 'pad_signal'
#	
#	example:
#	chip_pad,pad_signal,memory_byte_group,bank,vccaux,group,super_logic_region,io_type,nc_part
#	T12,DONE_0,NA,0,NA,NA,CONFIG,NA,
#	N11,DXP_0,NA,0,NA,NA,CONFIG,NA,
#	K12,GNDADC_0,NA,0,NA,NA,CONFIG,NA,
#	K11,VCCADC_0,NA,0,NA,NA,CONFIG,NA,
#

# board table - path to CSV describing board connector pins
#	Required columns board,conn,conn_pin,chip_pad
#	
#	example:
#	board,conn,conn_pin,chip_pad
#	ZB,JA,P01,Y11
#	ZB,JA,P02,AA11
#	ZB,JA,P03,Y10
#	ZB,JA,P04,AA9
#	ZB,JA,P05,GND
#	ZB,JA,P06,PWR
#	ZB,JA,P07,AB11

# user supplies xdc_set_iostandard and xdc_add_pin commands in the job
# ex:
# xdc_set_iostandard( "LVCMOS33" )		# straight xilinx terminology
# xdc_add_pin( "dac_sclk",		"JA", "P01" )
# xdc_add_pin( "dac_sdata",		"JA", "P02" )
# xdc_add_pin( "dac_sclk",		"JA", "P03" )
# xdc_write_xdc( "dac.xdc" )
#
# desired output looks like
# # -----------------------------
#	# dac_sclk:	JA.P01 => Y11 => IO_L10P_T1_13
#	set_property PACKAGE_PIN Y11 [get_ports {dac_sclk}]
#	set_property IOSTANDARD LVCMOS33 [get_ports {dac_sclk}]
# # -----------------------------
#	# dac_sdata: JA.P02 => AA11 => IO_L8P_T1_13
#	set_property PACKAGE_PIN AA11 [get_ports {dac_sdata}]
#	set_property IOSTANDARD LVCMOS33 [get_ports {dac_sdata}]
#
# etc.  each pin gets a link to a signal, and an iostandard set.

def xdc_start( chiptable, boardtable ) ###_EXT_### start up a collection of XDC constraints

	chiptablepath = find_file( chiptable )
	$g_xdc_chiptable = CSV.read( chiptablepath, $csv_options );
	
  if ($debugmode!=0)
		printf( "\n --- chip table %s ---", chiptablepath.realpath )
		$g_xdc_chiptable.each do |row| printf( "\n%s %s", row[ :chip_pad ], row[ :pad_signal ] ) end
    printf( "\n" )
	end

	boardtablepath = find_file( boardtable )
	$g_xdc_boardtable = CSV.read( boardtablepath, $csv_options );

  if ($debugmode!=0)
		printf( "\n --- board table %s ---", boardtablepath.realpath )
		$g_xdc_boardtable.each do |row| printf( "\n%s %s %s %s", row[ :board ], row[ :conn ], row[ :conn_pin ], row[ :chip_pad ] ) end
		printf( "\n\n" )
	end	
	
	# default iostandard
	$g_xdc_iostandard = "LVCMOS33"
	
	# empty the text buffer
	$g_xdc_text = ""
end

def xdc_set_iostandard( str ) ###_EXT_### set the current pin IOSTANDARD that will apply to subsequent pins
	# not much to do (could do some validation though)
	$g_xdc_iostandard = str
end

def xdc_add_pin( netname, conn, connpin ) ###_EXT_### add one pin mapping to the collection
	# signal is a net name in the verilog module - i.e. leds_out[0]
	# conn is a connector label for the board (JA, JB, etc)
	# connpin is a designator of a pin on the connector - e.g. P01, P02, etc.

	# using the board table, map conn and conn_pin to the chip_pad
	boardtable_rows = $g_xdc_boardtable.select{ |row| (row[:conn]==conn) && (row[:conn_pin]==connpin) }

	if (boardtable_rows.size == 1)
		# found the connector in the board table, and now we know the pad name
		chip_pad = boardtable_rows[0][:chip_pad]
	
		# look up the pad name so it can be mapped to the internal signal name
		# this is just for a comment to be left in the XDC for sanity checking
		chiptable_rows = $g_xdc_chiptable.select{ |chiprow| (chiprow[:chip_pad]==chip_pad) }
		if (chiptable_rows.size == 1)
			pad_signal = chiptable_rows[0][:pad_signal]
		else
			pad_signal = "???"
		end

		if ($debugmode!=0)
			printf( "\n netname %s mode %s -> conn %s %s ( pad %s signal %s )", netname, $g_xdc_iostandard, conn, connpin, chip_pad, pad_signal )
		end

		pin_text = ""	
		# emit comment
		pin_text += sprintf("\# %-20s: %s.%s ==> %s ==> %s\n", netname, conn, connpin, chip_pad, pad_signal )
				
		# emit PACKAGE_PIN line which connects signal to pin
		pin_text += sprintf("set_property PACKAGE_PIN %-8s    [get_ports { %s }]\n", chip_pad, netname )

		# emit IOSTANDARD line which configures pin voltage etc
		pin_text += sprintf("set_property IOSTANDARD %-12s [get_ports { %s }]\n", $g_xdc_iostandard, netname )

		# whitespace
		pin_text += "\n"

		$g_xdc_text += pin_text
		if ($debugmode!=0)
			printf("\n%s",pin_text)
		end
	else
		printf("\n ** xdc_add_pin: connector %s.%s matches multiple rows in board table",conn,connpin )
		abort "stopping"		
	end
end

def xdc_add_iostandard_for_bank( bank, standard )
	#one way
	ios_text = sprintf("set_property IOSTANDARD %s [get_ports -of_objects [get_iobanks %s]];\n",standard.to_s, bank.to_s )

	#other way
	#ios_text = sprintf("set_property IOSTANDARD %s [get_ports -filter { IOBANK == %s } ];\n",standard.to_s, bank.to_s )
	
#	$g_xdc_text += ios_text
end

def xdc_write_xdc( xdcname ) ###_EXT_### write out the final XDC test for this collection of pins
	write_generated_file(xdcname, $g_xdc_text)
end


###############################################################################
###############################################################################
###############################################################################

# print help function (basics)

def print_help

helptext=<<-EOF
genx [OPTION] <source verilog file paths>

--help:            show help
--helpfunctions    list out functions in genx.rb that are available to jobs
--xprfile <file>   supply path to targeted Vivado XPR project (required)
--gendir <dir>     supply desired directory to write generated files. (optional)
--define <symbol>  add global definition 
--axidebug         turn on AXI debugging

Tasks that genx can help with:
	- Defining symbols that are visible both to Verilog code and Ruby job code
	- Generating function lookup tables and .mif/.v files to match.
	- Generating AXI glue code to match a user defined set of registers in a module
	- Generating constraints (XDC file) to map signals to physical connector pins on a board
	
example:
	cd ~/myproject
		# ^^ say there's a Vivado project at ~/myproject/test1/test1.xpr, and embedded jobs inside ~/myproject/main.v

	genx.rb --xprfile ~/myproject/test1/test1.xpr main.v
		# ^^ results pushed to myproject/test1/test1_gen/ (auto selected output dir, based on XPR filename)
		
	genx.rb --xprfile ~/myproject/test1/test1.xpr --gendir ~/myproject/test1/gensrc main.v
		# ^^ results pushed to myproject/test1/gensrc/ (explicitly selected output dir)

Functions available to jobs: try genx.rb --helpfunctions

EOF

	puts("#{helptext}")
end


def print_help_functions

helptext=<<-EOF
Functions available to jobs:
EOF

# find "EXT" lines

	path_to_self = (File.expand_path $0)

	marker= "###" + "_EXT_" + "###"

	File.foreach(path_to_self).with_index do |line, line_num|
		line.chomp!
   	if (line.match(marker)) then
   		descrip = line.split(marker)
	  	helptext += sprintf("%s\n        %s\n",descrip[0].strip, descrip[1])
  	end
	end	# end line loop

	puts("#{helptext}")
end

###############################################################################
###############################################################################
###############################################################################
# option processing and source filename pickup

opts = GetoptLong.new(
  [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
  [ '--helpfunctions', '-f', GetoptLong::NO_ARGUMENT ],
  [ '--debug', '-d', GetoptLong::NO_ARGUMENT ],
  [ '--axidebug', '-A', GetoptLong::NO_ARGUMENT ],
  
  [ '--xprfile', '-x', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--gendir', '-g', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--define', '-D', GetoptLong::REQUIRED_ARGUMENT ]
)

opts.each do |opt, arg|
  case opt

    when '--help'
    	print_help
    	
    when '--helpfunctions'
    	print_help_functions
    	
    when '--debug'
    	$debugmode = 1
    	
    when '--axidebug'
    	$axidebug = 1
    	
		when '--xprfile'
			set_xpr_file_path( arg.to_s )
			
		when '--gendir'
			set_gen_dir_path( arg.to_s )
			
		when '--define'
			add_define( arg.to_s )
  end
end

###############################################################################
###############################################################################
###############################################################################
# job processing functions

$g_job_error = 0;
$g_job_error_totalcount = 0;

## run one job
def process_job(job_header,job_body)
	printf("\n job '%s' : processing..",job_header )

	$g_job_error = 0;
	eval(job_body)
	if ($g_job_error != 0)
		$g_job_error_totalcount = $g_job_error_totalcount+1;
		printf("\n job '%s' : error %d\n",job_header,$g_job_error )
	else
		printf("\n job '%s' : completed.\n",job_header )
	end
end	  		

## run jobs within file
def process_file_jobs( filename )
	# open up the file
	# find matched blocks of @@job ... @@end-job
	# process each one

	checkpoint_defines()
		
	job_active = false
	job_header = ""		# whatever came after the colon
	job_body = ""			# lines between job and end-job
	
	File.foreach(filename).with_index do |line, line_num|
		line.chomp!
		#puts "#{line_num}: #{line}"
   	if (!job_active && line.start_with?("/*@@job:")) then
	  		if ($debugmode != 0) then
	  			printf("\n found job: [%s]",line)
	  		end
	  		job_active = true
				job_header = ""
				job_body = ""
	
	  		# extract job header
	  		job_header = line;
	  		job_header.gsub!( "/*@@job:","")
  	elsif (job_active && line.start_with?("@@end-job*/")) then
	  		if ($debugmode != 0) then
		  		printf("\n found end-job: [%s]",line)
		  	end
	  		job_active = false
	  		
	  		# run job:
				process_job(job_header,job_body)	  		
  	elsif (job_active)
  		job_body << line + "\n"
  	end
	end	# end line loop
	printf("\n%d total job errors\n",$g_job_error_totalcount)
	
	restore_defines_from_checkpoint()
end # end def

###############################################################################
###############################################################################
###############################################################################
# actual processing starts but only if an XPR has been named

if ($g_xpr_file_path)
	# absorb filenames showing up after the options
	while (ARGV.count >0) do
		add_source_pathname(ARGV.shift)
	end
	
	if ($debugmode != 0)
		# dump out stuff for debugging
		printf("\n xpr path is %s", $g_xpr_file_path.realpath )
		$g_defines.each {|key, value| printf( "\n define #{key} = #{value}" ) }
		$g_source_pathnames.each {|pathname| printf( "\n source #{pathname.realpath}" ) }
		printf("\n")
	end
	
	# make sure output directory is ready
	if (! check_gen_dir_path)
		# auto select a folder based on the XPR project filename.
		set_gen_dir_path("")
	end
	
	# run jobs
	$g_source_pathnames.each{|pathname| process_file_jobs(pathname.realpath) }
end

	
# probably need to report some error count / return status here
