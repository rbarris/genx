# genx
Script for Xilinx/Vivado/Zynq developers.  Automates generation / maintenance of AXI glue, XDC files, lookup ROMs, etc.

If you're looking for the 'starter' demo Vivado/XSDK project referenced here in the README, an archive is stored on Google Drive:
    https://drive.google.com/open?id=0B62pcVtpg2pVRGVTcDFtaTk2ckU

BACKGROUND

    Rob Barris - rbarris@gmail.com - http://github.com/rbarris - @rbarris on Twitter

     I've built a modest variety of microcontroller projects on chips like 68HC11/12, and Cortex M3/M4.  When I got started with Xilinx/Vivado/Zynq and FPGA programming, I started running into some tasks that were distracting and error-prone.  To counter them, I started writing 'genx', a multi-purpose tool that can automate these tasks while working with Vivado 2016.1 or higher:

     - generating XDC files to connect physical board pins to logic.
     - tracking the mapping of board pins to chip pins, possibly for multiple boards
     - generating lookup tables in project-ready form (ROMs with MIF files and Verilog module wrappers)
     - maintaining a CPU-visible register interface to user logic ("AXI glue")
     - providing a means to keep Verilog, C, and Ruby code in sync with defines/ifdefs.

     I wanted to be able to script these processes in a concise way. The script is intended to re-generate needed output files on demand, and provide flexibility in programming, to allow for support of multiple board variants and build configurations using common source code.

     I like working with text and scripts, and revision control, and maintaining clear separation between stuff I write and the somewhat cluttered file structure inside a Vivado project folder.  'genx' is set up so you can keep your written source in one place, and send the generated products to a folder specific to the Vivado project where the actual build / simulation / synthesis & bitstream generation gets done.  This makes it easier to keep all your source text in revision control, and makes it a little easier to navigate.
     Some improvements made in Vivado 2016.1 make this approach more practical, in particular the ability to bypass "IP Packager" and instantiate an HDL module from your source file, directly into a Vivado block design.

     The primary role of 'genx' is to ease the process of creating a Vivado-compatible module which has a simple AXI slave interface on one side, external interface pins on the other, your custom logic in between - in the best case you can get all that done in a single source file.  (The AXI interface and the external pins are optional in your module design, but when you do want to add them, 'genx' can make it a lot easier.)

    'genx' runs on Ruby 2.0 or higher on Linux (I write and test on Ubuntu 14.04), and the segments of job code that it will execute in a project are also written as Ruby code.

THEORY OF OPERATION

    'genx' is invoked with a minimum of two arguments, the path to the target XPR project (--xprfile), and then the filenames of Verilog source files that contain tasks for 'genx' to perform with respect to that project.  The tasks are embedded in the source files using block comments with special markers, they look like this:

/*@@job:my_define_setup

add_define("BOARD_ZEDBOARD")
add_define("ENABLE_FEATURE1")
add_define_value("FREQUENCY",440)

write_defines_verilog( "my_defines.vh" )

@@end-job*/

     What 'genx' does, is to find these chunks of Ruby code demarcated by the job and end-job markers, extract all the lines of text between the markers, and execute those chunks of code directly (in the same order as they are written in the file) - within the context of the genx script itself.   What that means is the Ruby code written in the block comment above gets virtually 'copy and pasted' into the body of the genx script and executed (specifically accomplished by way of the Ruby 'eval' command). This has some implications:

    - it's Ruby code, you can do anything.  You can define functions, you can reference globals, write loops, etc. Don't forget you have to use Ruby's # style comments inside job blocks, not // or /* */.
    - you can call functions provided for you inside 'genx' - a list is printed if you run genx.rb --helpfunctions.
    - you can have global side effects. For example, the add_define calls above, add entries to a hash table which can be referenced by subsequent jobs in the source file.  This is a feature.
     - you can create or trigger bugs which will abort the script too!

    You can cram all the tasks you want to handle into a single job, or break them up and put a label on each one of them.  In the demo code they are broken up into functional groups: setting up defines, pins, AXI registers, and ROM tables.

DEMO WALKTHROUGH 

     'genx' has two subfolders: bin and lib.  'bin' has the genx.rb script in it.  'lib' has some support files, in particular CSV table files which describe the chips and boards supported - presently just Zynq-7010/7020 and Zedboard. Snickerdoodle is next on my to-do list; but writing new table CSVs in the lib dir is not too difficult if you want to add new ones.

     You'll probably want to add genx/bin to your executable $PATH.  If not you can of course invoke it by explicit path or by an alias etc.

     Navigate to the demo folder ('genxdemos') and examine starter.v... and note the subfolder where the actual Vivado project is located ('starter_zb').

     Return to shell and verify you are set to the 'genxdemos' working directory, then run genx as shown below.

     genx.rb --xprfile ./starter_zb/starter_zb.xpr starter.v
    ( a script is included in the demo directory "do_starter_gen.sh" which can do this more conveniently)

     The arguments inform 'genx' where the target Vivado project is located, and the name of the source file to scan, which contains the job code specific to the project.

     After 'genx' runs, a number of files should have been generated in the 'gen' directory inside 'starter_zb'.  The 'gen' directory will be created if it doesn't already exist.  These include

     - Verilog and C headers with desired defines expressed - "starter_defines.vh" / "starter_defines.h"
     - Verilog header with AXI register glue code - "starter_glue.vh"
     - C header with AXI register offsets - "starter_regs.h"
     - a lone .v file including module declarations that match the collection of ROM .mif files - "roms.v"
     - an .xdc file - "pins.xdc"
     - a number of ROM ".mif" files (memory initialization data)

     The 'gen' folder and the output files it contains should be treated as completely disposable - everything in it was generated in response to Ruby code embedded in starter.v, and the helper functions inside 'genx'.  To confirm this, you can delete the 'gen' folder inside starter_zb, and run the script again and it will be completely reconstituted.

     If this were a brand new Vivado project it would then be necessary to add the files in the gen folder (and starter.v) to the project's source roster.  These steps are covered under "COLDSTART" below.  In the starter demo, those files should already be visible in the Vivado project and adding them should not be necessary.

DEMO CODE

    The demo code is arranged in a series of sections, each affiliated with some combination of output pins, input pins, CPU-visible registers, and user logic.

     On Zedboard, each section winds up driving one of the eight LED's on the board (LD0-LD7), and possibly reading the corresponding switch (SW0-SW7).  The state of the LED pins is also mirrored to the 8 signal pins on connector JB (PMod).

    The sections are meant to show a progression from a very simple piece of user logic to more complex forms that also involve code running on the ARM CPU and communicating through registers on the AXI bus.

     Demo sections 0-3 have zero CPU involvement; the higher numbered sections have CPU software involvement and AXI-interface register glue.  The demo CPU side runs "bare metal" on the Zynq's ARM processor, there's no Linux involved.

     Since demos 0-3 don't involve the CPU, they will start running as soon as the FPGA has been programmed and comes out of reset.

     Starting with all four SW0-SW3 turned off, you'll see the LEDs counting in binary (a '0' being shown as a dim PWM level, and a '1' being a brighter level).  As you turn on each switch, that individual demo will switch from the binary counting animation to a unique pattern for each:

demo0: animate "randomized" (bit reverse of upper systick bits selects brightness).
demo1:  animate using sinewave ROM.
demo2: animate using first quadrant of a sinewave ROM to effect an "attack/decay".
demo3: animate using an LFSR random number generator.

    All the Verilog code for these is contained in starter.v.

    To run the CPU based demos, you will need to launch the Xilinx SDK.  Assuming you made some change to the genx job code st the top of starter.v, or any change that would affect the built hardware, you would need to follow these steps to re-spin the bitstream and take it over to the XSDK:

    a) re-run genx as shown above so all the generated files are up to date.
    b) In Vivado, Generate Bitstream (which will trigger synthesis, implementation, etc)
    c) In Vivado, "Export Hardware" to the default location where XSDK can get to it ("local to project")
    d) Launch Xilinx SDK or bring it to foreground
    e) In XSDK, rebuild the software project(it may do this automatically, or it may warn you first that the platform changed, as expected, and then rebuild)
    f) In XSDK, "Program FPGA" (toolbar icon that looks like four little squares with a wire winding through them)
    g) Launch the test application (helloworld.c) in the system debugger.

     If you are iterating on the software side of things, it will be the familiar compile-edit-run cycle, should not be necessary to re-program the FPGA or any of the more time consuming Vivado steps, until it's time to make a code change in the logic, at which point you go back to step 'a'.     

    Once FPGA is programmed and app is launched in debugger, even if code is stopped you should still see the low four LEDs animating.  When the starter demo's main loop begins to run, then you should see additional animation on the upper LED's.

    You can add "regs" to the XSDK debugger variable pane and examine the fields of the PL hardware that are exposed by AXI bus.

    On my system I am able to monitor the Zedboard UART output using minicom and port /dev/ttyACM0 at 115200 baud, so I see the "Hello World" and the periodic prints from the demo loop each time it notices the hardware FIFO in the demo design emptying and then refills it with 255 samples of random PWM fade values.


CAVEATS / Q&A / TBD

Basically you only need to re-run 'genx' when you've changed or added something that would affect the output file contents.  In practice the runtime of the script is typically so short that it's fine to be cautious and just run it at will.

Vivado will frequently prompt you to "Refresh Changed Module" when you have made changes to module source, port list, etc on a source module which is active in the Block Design. It may be best to re-run 'genx' prior to acknowledging the "Refresh" button, to ensure that Vivado sees the latest generated files.

Vivado may get confused if you have one of the generated files open in the editor and it gets regenerated out from under it.  The editor notices this situation and prompts you to reload, but I have seen cases where the IDE acted like it was still honoring the old code and not the new version on disk - this would persist until I closed the stale editor view.

How do I connect a pin to a signal ?
    - see usage of "xdc_add_pin" in the demo.

How do I add a CPU visible register in the AXI glue ?
    - see usage of "axi_add_reg" in the demo.

How do I set up an AXI glue register to trigger action upon read or write?
    - see usage of registers with the readthrough / writethrough modes.

How do I add a ROM with my own function or data in it ?
    - see the usage of "multi_generate_lut" in the demo, you can pass any Ruby function in.  "idx" and "lim" represent the index of the sample value being calculated, and the array size of the ROM being built.

How do I target more than one board or chip?
    - You can do this manually with a selection of add_define calls at the top of your Ruby job code, and use the is_defined function in Ruby job code, the `ifdef `SYMBOL syntax in verilog, and the #ifdef syntax in C, to drive conditional execution / compilation.  Keep in mind that separately targeted Vivado XPR projects will/should have separately generated source file folders set up.
    - Note you can also do Ruby string operations on the pathname of the XPR target project ($g_xpr_file_path) - so by some basic encoding of target hardware in the project names, you can make this automatic and hand-editing-free.

How do I add support for a board or Xilinx chip that isn't already handled ?
    - You just need new CSV tables that follow the conventions in the lib folder.

How do I place my new module into a block design that can run on hardware ?
    - The 'genx' process needs to be completed.
    - Your main source file needs to be added to project.
    - The generated output folder's contents also need to be added - this will include .v / .vh / .mif / .xdc files.

How do I simulate first and save a lot of time and suffering?
    - Simulation can save you ludicrous amounts of time and struggle.  But I found out, when I tried to simulate my component with an AXI slave interface, that you can't simulate a "whole system" including the Zynq processor core, using the webpack edition of Vivado.  In response I wrote some Verilog testbench scripts for setting up "fake CPU" AXI-master behavior that are sufficient to do basic "register setup" sequences and allow for a simulation of your module.  I intend to clean those up and share them as well.
     Turnaround time for a change can be much quicker in simulation than going through real synthesis/implementation/bitstream, especially for a beginner where the user logic component is modest in size early on.

How can/should files/folders be arranged ?
    - I like to have a main folder which has my sources and notes in it, and is revision controlled.  Then I like to put Vivado project folders within that (I don't put Vivado folders/contents into source control because that is challenging to do correctly, only the stuff I am writing gets checked in).  But 'genx' lets you have things placed wherever you want them to go.

How can I add a button to the Vivado toolbar which can run genx for me when I want?
    TODO - this should just require a snippet of Tcl glue (vivado uses Tcl for everything internally).

COLDSTART

How to bring up a new Vivado+Zynq+genx project from scratch, this one targets Zedboard.  Example follows the flow I used to create the starter_zb project in the link at top of this README.

Stage 1:

Create a folder that will hold your source code. (ex: stuff)

Start Vivado.  You may want to go to Tools->Options... dialog and set the default Vivado "Target Language" to Verilog (since 'genx' and its author have not yet learned VHDL, sorry)

Click Create New Project - navigate to your new folder and create the project there.  ex: "trafficlight"

Directories "stuff" (you created) and "stuff/trafficlight" (Vivado-created) should exist, and the path to the XPR file should be stuff/trafficlight/trafficlight.xpr.

Motivation for this naming and arrangement: to allow multiple child projects to live in the same hosting folder with one set of sources feeding them (in 'stuff').

Select RTL Project, checkbox set "do not specify sources at this time."

Select your board from board menu, Zedboard in this example.

Finish.  Stage 1 complete, you have a Vivado project in the right location which is configured for your board of choice.

Stage 2:

Under IP Integrator in the Flow Navigator, click Create Block Design.  It will prompt you for naming, I name my top-level BD's "system", you can pick whatever you like.  Blank Diagram panel appears.

Add IP for the Zynq PS: click the Add IP Button (little chip with a plus sign next to it, on the left edge of the Diagram editor view).

In the Search panel for Add IP, type in Zynq and it should filter out everything but the ZYNQ7 Processing System.  Double click that IP entry to add it to the Block Design (BD).

At top of Diagram Editor, a link/button for Designer Assistance "Run Block Automation" will appear, you should click that.  Click OK to the design preset dialog, be sure "Apply board preset" is checked/enabled.

Diagram should update to show a ZYNQ7 Processing System in the center.  Click and drag a wire from the M_AXI_GP0_ACLK to the FCLK_CLK0 pin to connect fixed clock 0 to the AXI bus clock.

Click the Validate Design button on the left edge of the Diagram Editor, you should get a "no errors in design" confirmation.

Go to the Sources panel and make sure Hierarchy/Sources tab is active at the bottom of the panel.  Expand the "Design Sources" section in the panel and you should see "system.bd" present, this represents the block design just created.

Right click that "system.bd" entry and select "Create HDL Wrapper" on it.  Leave the checkbox in the Create HDL Wrapper setup dialog set to "Let Vivado manage wrapper and auto-update" and click OK.  This step is really really important.  Don't skip it.  Strange build problems will happen later!

In Sources panel, note the creation of system_wrapper.v, this is a top level source file that tracks the components in the BD and how they are linked together.

Stage 2 is complete, now you have a project with a Zynq component instantiated.

Once I get to this point in setup I like to Save Project As... and make a copy of this checkpoint somewhere.  Then the next time I need to crank up a new project for this particular board configuration, I can skip all the steps above.  I find the "Save Project As..." command to be the most convenient way of cloning a working project under a different name (i.e. you should avoid copying the project folder and renaming it etc, that way lies trouble)

Stage 3: now we can trigger 'genx' to look at our sources and generate new outputs, add the combination of our source with the generated files to the project, and build.

Assuming you have a central Verilog source file analogous to the "starter.v" file, in this example it would be something like 
    "stuff/trafficlight.v"

then the genx invocation would be (assuming you are in 'stuff' working directory):

    genx.rb --xprfile ./trafficlight/trafficlight.xpr ./trafficlight.v

and generated code will arrive in stuff/trafficlight/gen.

After that you will need to make three source additions to the Vivado project, one file that you are writing, then all the ones generated by 'genx'.
    'stuff/trafficlight.v' (your design source)
    'stuff/trafficlight/gen' folder (add as a directory of design source)
    'stuff/trafficlight/gen/pins.xdc' (add as a constraint file - be sure to set the right checkbox in the add dialog)

Once that is done, and assuming your code compiles OK, you can add your module to the block design.  This is done by right clicking inside the Diagram Editor for the block design, and selecting the "Add Module..." command.  The resulting dialog will prompt you for a module name, and you should be able to find your module in the list and drop an instance of that module into the block design.  If you have it built up with an AXI interface, Vivado will prompt you to run connection automation to get the AXI bus wired up (some new components are likely to appear such as the AXI master switch at this step).

At this point you should be able to see a complete block design showing the Zynq PS, the AXI master switch, and your component linked together.

if your component has pins that are intended to mate up with external pins, you'll need to click each one and hit Ctrl-T for "Make External".  In that fashion, pins with names that match up with your XDC file (perhaps genx generated!) will get properly routed when you go to build, and your logic will get connected to the real world.

Now you can synthesize and generate bitstream etc.  If you hit errors which require you to change the 'genx' job code, make sure to re-run genx after saving out edits there.

TODO'S

Add board-table CSV files in 'lib' for krtkl's snickerdoodle / snickerdoodle-black
Extend "starter" demo to run on snickerdoodle
Write some Tcl glue to make it easier to invoke 'genx' from inside the Vivado IDE as a button
