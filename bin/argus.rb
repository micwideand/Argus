require 'yaml'

VERSION = "0.0.3"

class Argus
	# class variables
	# eventlogs									hash using dates as key and an array with the names of the logfiles as value
	# errmsgs										errorcodes and their meaning according errmsg file 
	# readable_info							data from the logs fit for human reading
	# device_id									hex codes and the device it refers to, used together with ss_sub_id
	# gts_cmd										commands used for GTS communication
	# ss_sub_id									sub unit the device code refers to, used together with device_id
	# xc_cmd										commands used for XC communication
	# xc_errmsg									hexadecimal errorcode and it's meaning in text
	# xc_nack										clear text information related to nack specific xc error messages, used with xc_errmsg
	# details 									hash table containing the meaning of error bits cfr service manuals
	# ct_type										constant used to load proper values used for error translotions
	# ct_with_xc3								list of ct systems using the XC3 formatting 
	# ct_with_sru								list of ct systems using the SRU formatting 
	# 		XC2 formatting is recognized as being non-sru and non-xc3.  The decoding is based on the fact that the sequence begins with 3 or 4
	
	attr_accessor :eventlogs, :errmsgs, :readable_info, :device_id, :gts_cmd, :ss_sub_id, :xc_cmd, :xc_errmsg, :xc_nack, :details, :ct_type, :ct_with_xc3, :ct_with_sru
	def initialize
		#concatenate string to 1 line when explanatory text for an error is more than one line
		#as long as errmsg keeps the same syntax, modifications will be handled without trouble
		@errmsgs = File.open("../etc/errmsg", "r").read.gsub("\\n\n","").gsub(/\s{3,}:/, "")
		
		
		@device_id = YAML.load(File.open("../etc/device_id.yaml", 'r'))
		@gts_cmd = YAML.load(File.open("../etc/gts_cmd.yaml", 'r'))
		@ss_sub_id = YAML.load(File.open("../etc/ss_sub_id.yaml", 'r'))
		@xc_cmd = YAML.load(File.open("../etc/xc_cmd.yaml", 'r'))
		@xc_errmsg = YAML.load(File.open("../etc/xc_errmsg.yaml", 'r'))
		@xc_nack = YAML.load(File.open("../etc/xc_nack.yaml", 'r'))
		
		@ct_with_xc3 =  File.readlines('../etc/ct_with_xc3.txt')
		@ct_with_xc3.map! do |ct| 
			ct.strip
		end
		
		ct_type
		
	end
	
	def ct_type
		# puts "Arguments received are #{ARGV}, ARGV is of type #{ARGV.class} the first element is -#{ARGV[0]}- and the second is -#{ARGV[1]}-"
		unless (ARGV[0] == "" or ARGV[0] == nil)
			@ct_type = ARGV[0].strip
		else
			@ct_type = "one"
		end
		puts "Error decoding will be done for a #{@ct_type}"
		
		@details = YAML.load(File.open("../etc/#{@ct_type}.yaml", 'r'))
		
		ct_with_sru = File.readlines('../etc/ct_with_sru.txt')
		ct_with_sru.map! do |t| 
			t.strip
		end
		# puts ct_with_sru
		if ct_with_sru.include? @ct_type
			@details.merge!(YAML.load(File.open("../etc/xc_sru.yaml", 'r')))
		else
			@details.merge!(YAML.load(File.open("../etc/xc.yaml", 'r')))
		end
		
		@details.merge!(YAML.load(File.open("../etc/xc2.yaml", 'r')))
		@details.merge!(YAML.load(File.open("../etc/xc3.yaml", 'r')))
	end
	
	def find_eventlogs_by_date
		# date format used in the naming of eventlogs (Evt and Evtx files)
		# errlog.ApplEvent.2016Jul21-100214.Evtx
		# date format used in the naming of eventlogs most likely referring to a shutdown
		# errlog.ApplEvent.20160721100010.Evtx
		@eventlogs = Hash.new
		(Dir.glob("../evtlogs/*.Evtx") + Dir.glob("../evtlogs/*.Evt")).sort.each do |file|
			date = file[/(\d{4}\D{3}\d{2})|(\d{8})/]
			
			if @eventlogs[date]
				@eventlogs[date] += [file]
			else
				@eventlogs[date] = [file]
			end
		end
		
		puts "find_eventlogs_by_date - event log files grouped by date \n#{@eventlogs.to_a.join("\n")}"			
	end
	
	def eventlogs_to_txt
		decode_main = ""
		decode_sub = ""
		@eventlogs.each do  |date, files|
			readable_info = Array.new
			output = File.open("../summary/#{date}.html", "w")
			
			output.write('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
						<html xmlns="http://www.w3.org/1999/xhtml"> <head> <title>Aquilion Application Eventlog summary</title>
						<meta http-equiv="content-type" content="text/html;charset=utf-8" /> <style type="text/css">')
			output.write(File.read('../etc/toshiba.css'))
			output.write('</style> </head> <body> <h1>Toshiba Medical Systems CT Application Event Log.</h1>')
		
			output.write('<em>Based on the Toshiba training documentation "\6_Training notes\2_A-series_General\H_Operation_Software_PC"<br/>
						"20100720 Aseries - Logs Manual.pdf"<br/>
						"TAMS Error Log Translation Manual.pdf"<br/>
						"TAMS ErrorLog Presentation.pdf"<br/><br/>
						Decoding of XC detail status for XC2 based on FSM3785/FSM4086 and  for SPAG4 on "Aquilion - Spag4 XC DETAIL STATUS detail error.pdf".<br/><br/>
						GNS refers to OPCONT A, SCRT or KTCONT.</em><br/><br/>')
			output.write("\n")
			
			files.each do |file| 
				readable_info.concat( File.open(file, "rb").read.scan(/(\d\d:\d\d:\d\d\.\d\d\d.*?)\000/m) )
			end
			
			puts "readable_info class is #{readable_info.class}, the size/number of lines is #{readable_info.size}"
			
			gts_part = 1
			lmudat_part = 1
			
			errorcodes = Hash.new
			
			readable_info.each do |line|
				# puts line.class, line.size
				line_string = line[0].strip
				
				# look up the meaning of errocodes
				if line_string[/(.*errdspmgr.*errcode.*)/i] 
					# according TAMS, the commbination 'errcode = 00000000 device = 00000000 processNo.= 8004' is not usefull for troubleshooting
					unless line_string.include?("errcode = 00000000 device = 00000000 processNo.= 8004") 
						error_time = line_string[/(\d\d:\d\d:\d\d\.\d\d\d)/]
						line[0] = "<a name=\"#{error_time}\"></a><errdspmgrdecoded>#{line_string}</errdspmgrdecoded> \n <errdecoded>#{error_meaning_and_dev_id(line_string).join("</errdecoded>\n<errdecoded>")}</errdecoded> \n"
						begin
							code_dev_proc = line_string.split("ErrDspMgr:")[1].strip
							if errorcodes.has_key?(code_dev_proc)
								errorcodes[code_dev_proc] << "<a href=\"##{error_time}\">#{error_time}</a>"
							else 
								errorcodes[code_dev_proc] = [error_meaning_and_dev_id(line_string), "<a href=\"##{error_time}\">#{error_time}</a>"]
							end
						rescue
							
						end
					else
						line[0] = ""
					end
				# elsif line_string[/(.*(nreceiver|itsrv|slclog|HipaaLoginCheck|batctl\.exe|receiver\.e|nscanserve|CNSSSLibControl|Dvdram_|NnotifyAge|fsys_sync|nfsys\.exe|fcmgr\.exe|lsys\.exe|lmdb\.exe).*)/i]
					# line[0] = ""
				elsif (line_string[/(.*rtmtalkd.*destination.*error.*)/i])
					line[0] = "<rtm>#{line_string}</rtm><br /><rtm>The fact that this line is related to RTM trouble (FC, network, IB or server) still needs to be confirmed.<br />Run getbirinfo for more information.<br />If an error occurs between RTM and a Secondserver, swap the Infiniband cable between the server indicated as being faulty and another one.  If the second server is a different one after reboot, consider changing the AVP modules.</rtm>"
				elsif (line_string[/(.*NumCtl\.exe.*f_GetSysEnv.*)/i])# and ARGV.include?("full"))
					puts line_string
					line[0] = line_string
				elsif (line_string[/(.*LKCheck\.c.*License = .*)/i]) #and ARGV.include?("full"))
					line[0] = "<licence>#{line_string}</licence>"
				elsif line_string[/(.*BrHrinfTblMake.*)/i]
					# puts line_string
					line[0] = "<hrinfo>#{line_string}</hrinfo>" 
				elsif line_string[/(.*mother board.*)/i]
					puts line_string
					line[0] = "<motherboard>#{line_string}</motherboard>" 
				elsif line_string[/(.*scst_ctrl\.c.*)/i]
					puts "SCST/SCRT/DAS information found #{line_string}"
					line[0] = "<scst>#{line_string}</scst>"
				elsif line_string[/(.*quectlmg.*)/] 
					line[0] = ""
				elsif line_string[/(.*EPselect key.*)/i]
					line[0] = line_string 
				elsif (line_string[/(.*getrawsize.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				# elsif line_string[/(.*fmgetidddiskspace.*)/i]
					# puts line_string
				elsif line_string[/(.*idddeviftlib.*)/i]
					if line_string.include?("state is 0x00")
						line[0] = "<idd>#{line_string}</idd>" 
					else
						line[0] = "<iddbad>#{line_string}</iddbad>" 
					end
				elsif (line_string[/(.*StartupList\.cpp.*)/i] and  ARGV.include?("full"))
					line[0] = "<startup>#{line_string}</startup>" 
				elsif (line_string[/(.*startscanplan.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*_couch_z.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*dssdispzoom.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.* rc_cond.*)/i] )
					line[0] = "<rccond>#{line_string}</rccond>" 
				elsif (line_string[/(.* rc_.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.* rc\..*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*scanmode.*)/i])
					line[0] = "<patient>#{line_string}</patient>" 
				elsif (line_string[/(.*olpsi_pln.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif( line_string[/(.*olpmlt_pln.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*updateaid.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*getdoseexparea.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.* ss==.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*inlimit.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*REALECCALC.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*adjustscanrange.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.* tpos.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*ssgetgtsxcstatus.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif line_string[/(.*dpsetacqdasmode.*)/i]
					line[0] = line_string 
				elsif (line_string[/(.*adaptive das gain.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*calib_inf.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*getacqrec.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*recon_.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.* vhp_.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*de_recon.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*helshttl.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[0][/(.*setviewreplace.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[0][/(.*index info in EPDB.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				elsif line_string[0][/(.*send shutdown request.*)/i] 
					line[0] = line_string 
				elsif line_string[/(.* group .*)/i] 
					line[0] = "<patient>#{line_string}</patient>" 
				elsif line_string[/(.* organ .*)/i]
					line[0] = "<patient>#{line_string}</patient>" 
				elsif line_string[/(.* patient_type .*)/i]
					line[0] = line_string 
				elsif line_string[/(.* selection .*)/i]
					line[0] = "<patient>#{line_string}</patient>" 
				elsif line_string[/(.* ep_id .*)/i]
					line[0] = "<patient>#{line_string}</patient>" 
				elsif line_string[/(.* m_[adefilprs].*)/i]
					line[0] = "<patient>#{line_string}</patient>" 
				elsif ((line_string[/(.*dicom.*)/i] and not line_string[/(.*DVD.*)/i]) and ARGV.include?("full"))
					line[0] = line_string 
				elsif (line_string[/(.*CTalkToErrDspMgr.*)/i] and ARGV.include?("full"))
					line[0] = line_string 
				# START look up the meaning of the detailed information
				elsif line_string[/(.*errdspmgr.* errdspmgr.*)/i]
					if line_string.include?("SSADI")
						decode_main = "SSADI"
						decode_sub = ""
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif (line_string.include?("GTS STATUS") or line_string.include?("GTS/GMS STATUS"))
						decode_main = "GTS_STATUS"
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("MUDAT")
						decode_main = "MUDAT"
						decode_sub = ""
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif (line_string.include?("GTS DETAIL STATUS") or line_string.include?("GTS/GMS DETAIL STATUS"))
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"
						decode_main = "GTS_DETAIL"
					elsif line_string.include?("XC STATUS")
						decode_main = "XC"
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("mode")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"  
						decode_sub = "mode"
					elsif line_string.include?("Slide")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"  
						decode_sub = "slide"
					elsif line_string.include?("LRside")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
						decode_sub = "lrside"
					elsif line_string.include?("free")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
						decode_sub = "free"	
					elsif (line_string.include?("censor") or line_string.include?("Sensor"))
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
						decode_sub = "censor"
					elsif line_string.include?("DDmotor")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"  
						decode_sub = "ddmotor"
					elsif line_string.include?("slide")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
						decode_sub = "slide"
					elsif line_string.include?("height")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"  
						decode_sub = "height"
					elsif line_string.include?("L/R")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"  
						decode_sub = "lr"
					elsif (line_string.include?("lmudat") or line_string.include?("SureCom"))
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"  
						decode_sub = "lmudat"
					elsif line_string.include?("detail")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>"  
						decode_sub = "detail"
					elsif line_string.include?("ERROR_INF")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("ss_state")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("ADD ERROR INF DUMP")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("addinf")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("seqcntl")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("init task")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					elsif line_string.include?("XC DETAIL STATUS")
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>" 
					end
					
					decode_mode = decode_main + "__" + decode_sub
					puts decode_mode
					
					if ( decode_mode == "GTS_STATUS__mode" and line_string[/mode.*exec.*error.*/i] )
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_gts_mode_exec_error(line_string).gsub("\n", "</decoded>\n<decoded>")}</decoded>"
					elsif ( decode_mode == "GTS_STATUS__slide" and line_string[/.*Interlock Slide.*/i] )
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_interlock( line_string).gsub("\n", "</decoded>\n<decoded>")}</decoded>"
					elsif ( decode_mode == "GTS_STATUS__free" and line_string[/.*free\&light.*/i] )
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_free_light_out2(line_string).gsub("\n", "</decoded>\n<decoded>")}</decoded>"
					elsif ( decode_mode == "GTS_STATUS__lrside" and line_string[/.*Interlock LRside.*/i] )
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n" #+ decode_interlock( line_string)	
					elsif ( ((decode_mode == "MUDAT__censor") or (decode_mode == "GTS_DETAIL__censor") or (decode_mode == "")) and line_string[/.*ErrDspMgr:.*3\S{15}.*/])
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_censor(line_string).gsub("\n", "</decoded>\n<decoded>")} </decoded>"
					elsif ( (decode_mode == "GTS_DETAIL__detail") and line_string[/.*ErrDspMgr:.*\S{32}.*/] )
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_gts_detail(line_string, gts_part).gsub("\n", "</decoded>\n<decoded>")}</decoded>"
						if gts_part == 1
							gts_part = 2
						else
							gts_part = 1
						end
					elsif ( (decode_mode == "GTS_DETAIL__ddmotor") and line_string[/.*ErrDspMgr.*\d{32}.*/])
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_ddmotor(line_string).gsub("\n", "</decoded>\n<decoded>")} </decoded>"
					elsif ( (decode_mode == "GTS_DETAIL__slide") and line_string[/.*ErrDspMgr.*\d{16}.*/])
						line[0] =  "<gtsinfo>#{line_string}</gtsinfo>\n" #+ decode_slide(line_string) + "</decoded>"
					elsif ( (decode_mode == "GTS_DETAIL__height") and line_string[/.*ErrDspMgr.*\d{24}.*/])
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n" #+ decode_height(line_string) + "</decoded>"
					elsif ( (decode_mode == "GTS_DETAIL__lr") and line_string[/.*ErrDspMgr.*\d{24}.*/])
						line[0] = "<gtsinfo>#{line_string }</gtsinfo>\n" #+ decode_lr(line_string) + "</decoded>"
					elsif ( (decode_mode == "GTS_DETAIL__lmudat") and line_string[/.*ErrDspMgr:.*\S{32}.*/] )
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_lmudat(line_string, lmudat_part).gsub("\n", "</decoded>\n<decoded>")}</decoded>"
						case lmudat_part
							when 1 then lmudat_part = 2
							when 2 then lmudat_part = 3
							else lmudat_part = 1
						end
					elsif ( (decode_mode == "XC__mode") and line_string[/mode.*exec.*error.*/i] )
						line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_xc_mode(line_string).gsub("\n", "</decoded>\n<decoded>")}</decoded>"
					elsif ( (decode_mode == "XC__detail") and  line_string[/.*ErrDspMgr.*\S{32}.*/])
						if @ct_with_xc3.include? @ct_type
							line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_xc(line_string, 'xc3').gsub("\n", "</decoded>\n<decoded>")}</decoded>"
						elsif (/4\S{31}/.match line_string)
							line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_xc(line_string, 'xc2').gsub("\n", "</decoded>\n<decoded>")}</decoded>"
						elsif (/3\S{31}/.match line_string)
							line[0] = "<gtsinfo>#{line_string}</gtsinfo>\n <decoded> \n#{decode_xc(line_string, 'xc').gsub("\n", "</decoded>\n<decoded>")}</decoded>"
						end
					end
					
				else
					line[0] = ""
				end
				# END lookup the meaning of error details / gts info
			end
			
			output.write("\n<br><br><argv>The commandline arguments used are: #{ARGV.join("\n")}</argv><br /><br />\n")
			
			output.write("\n<lijn>#{ '=' * 150}</lijn><br /><br />\n")
			
			errorcodes.each_pair do |key, value|
				output.write("<errdspmgrdecoded>#{key} occured #{value.size - 1} times</errdspmgrdecoded><br />\n")
				output.write("#{value.join("<br />\n")}<br />") 
				output.write("<br />\n")
			end
			output.write("\n<lijn>#{ '=' * 150}</lijn><br />\n")
			readable_info = readable_info.join("\n")
			# puts readable_info
			puts "cleaning up the html tags"
			begin
				readable_info.gsub!(/\n{1,}/, "<br />\n")
				puts '---- successfully cleaned up using gsub!(/\n{1,}/, "<br />\n")'
				readable_info.gsub!('<decoded></decoded><br />', "")
				puts '---- successfully cleaned up using <decoded></decoded><br />'
				readable_info.gsub!('<decoded> <br />', '<decoded>')
				puts '---- successfully cleaned up using <decoded> <br />'
				readable_info.gsub!("<decoded> </decoded><br />", "")
				puts '---- successfully cleaned up using <decoded> </decoded><br />'
				readable_info.gsub!("<decoded>\n </decoded><br />", "")
				puts '---- successfully cleaned up using <decoded>\n </decoded><br />'
				readable_info.gsub!("<decoded>\n</decoded><br />", "")
				puts '---- successfully cleaned up using <decoded>\n</decoded><br />'
				output.write(readable_info)
			rescue
				output.write("<br/><br/><noerror>-+-+-+-+-+-+- NO ERROR CODES FOUND OR DETAILED INFORMATION ABOUT GANTRY STATUS -+-+-+-+-+-+-</noerror><br/><br/>")
				output.write(readable_info.gsub!(/\n{1,}/, "<br />\n").gsub!("<br /><br />", "<br />"))
			end
			output.write("\n<br /><lijn>#{ '=' * 150}</lijn><br /><br />\n")
			output.close
			puts "../tmp/#{date}.html created\n" 
			
		end
		
	end
	
	def error_meaning_and_dev_id element
		# puts element, element.class
		result = String.new
		code = element[/(errcode\s*=\s*)(\S{8})/i,2]
		puts "errorcode found is #{code}"
		# search the errmsg file for all lines containing the errorcode.  some codes have different meanings
		result = @errmsgs.scan(/#{code} \S{8} \S{8} .*/i)
		
		# if the errorcode is not 100% present, an alternative is sought by only using the first 4 characters of the errorcode 
		if result.size == 0
			result = @errmsgs.scan(/#{code[0,4]}.{4} \S{8} \S{8} .*/i)
		end
		
		# XC nack errors are completed by using a specific file
		code_msg = code[0, 5]
		if ['b2502', 'b2504', 'b2520', 'b2580', 'b2510', 'b2540'].include? code_msg
			result = result + ["XC NACK error"] + [@xc_errmsg[code_msg]]
		end
			
		if ['b2510', 'b2540'].include? code_msg
			result = result + [@xc_nack[code[5, 3]]]
		end
		
		code = element[/(device\s*=\s*)(\S{8})/i, 2]
		puts "device found is #{code}"
		
		if code	
			result = result + ["device identified as MAIN device #{@device_id[code[0,4]]} and SUB device #{@ss_sub_id[code[4,8]]}"]
		else
			result = result + ["device could not be identified"]
		end
		
		return result
	end
	
	def decode_ddmotor element
		element = element.split("[ErrDspMgr.] ErrDspMgr: ")[1].strip
		puts "dd_motor code found is #{element}"
		result = String.new
		# feedback "dd motor information is #{element}"
		unless element == ("30" * 16)
			1.step(element.size - 1, 2) do |index|
				index2 = ((index -1 )/ 2) + 1
				detail = hex_to_bin element[index]
				unless detail == [0,0,0,0]
					errors = @details['DD motor'][index2]
					
					if errors
						errors.map! do |error|
							if detail[errors.index(error)] == 0
								error = 'not defined'
							else
								error = error
							end
						end
					
						errors.each do |error| 
							unless error == 'not defined' 
								result = result + "#### #{error} \n"
							end
						end
					end
				end
			end
		end
		return result
	end
	
	def decode_gts_mode_exec_error element
		puts "decode gts mode exec error #{element}"
		result = String.new
		gts_error = /error\[0x\S{8}\]/i.match element
		gts_error = gts_error[0].sub("error[0","").sub("]", "")
		
		element = element.scan /\[\w\w\]/
		
		begin
			element[0] = element[0][1,2]
			element[1] = element[1][1,2]
		rescue
			element[0] = ''
			element[1] = ''
		end
		
		if /.R/.match element[0]
			result = result + "#### Ready for operation (Ready)\n"
		else /.B/.match element[0]
			result = result + "#### Operation in progress (Busy)\n"
		end
		
		if @gts_cmd[element[1]]
			result = result + "#### " + @gts_cmd[element[1]] + "\n"
		end
		
		unless gts_error == "00000000"
			1.step(gts_error.size - 1, 1) do |index|
				# index2 = ((index -1 )/ 2) + 1
				detail = hex_to_bin gts_error[index]
				unless detail == [0,0,0,0]
					errors = @details['error'][index]
					
					if errors
						errors.map! do |error|
							if detail[errors.index(error)] == 0
								error = 'not defined'
							else
								error = error
							end
						end
					
						errors.each do |error| 
							unless error == 'not defined' 
								result = result + "\n#### #{error}"
							end
						end
					end
				end
			end
		end
		result = result + "\n"
		return result
	end
	
	def decode_interlock element
		result = String.new
		element = element.scan /\[\d\d\]/
		
		case element[0]
			when '[01]' then result = result + "#### Slide IN blocked,  OUT possible \n"
			when '[02]' then result = result +  "#### Slide IN possible, OUT blocked \n"
			when '[03]' then result = result +  "#### Slide IN blocked,  OUT blocked \n"
		else
		end
		
		case element[1]
			when '[01]' then result = result +   "#### UP blocked, DOWN possible \n"
			when '[02]' then result = result +  "#### UP possible, DOWN blocked \n"
			when '[03]' then result = result +   "#### UP blocked, DOWN blocked \n"
		else
		end
		
		case element[2]
			when '[01]' then result = result +  "#### Tilt + blocked, Tilt - possible  \n"
			when '[02]' then result = result +  "#### Tilt + possible, Tilt - blocked  \n"
			when '[03]' then result = result +  "#### Tilt + blocked, Tilt - blocked  \n"
		else
		end
		
		# feedback result
		return result
	end

	def decode_free_light_out2 element
		result = String.new
		puts "decode_free_light_out2 for #{element}"
		element = element.scan /\[\d\d\]/
		
		case element[0]
			when '[01]' then result = result +  "#### Free mode on, Projector off \n"
			when '[02]' then result = result +  "#### Free mode off, Projector on \n"
			when '[03]' then result = result +  "#### Free mode off, Projector off \n"
		else
		end
		
		case element[1]
			when '[01]' then result = result +  "#### Out2censor is on \n"
		else
		end
		
		return result
	end
	
	def decode_censor element	
		# puts "decoding censor information"
		
		element = element.split("[ErrDspMgr.] ErrDspMgr: ")[1].strip
		result = String.new
	
		puts "censor information is #{element}"
		unless element == "3030303030303030"
			1.step(element.size - 1, 2) do |index|
				index2 = ((index -1 )/ 2) + 1
				detail = hex_to_bin element[index]
				unless detail == [0,0,0,0]
					errors = @details['censor'][index2]
					
					if errors
					errors.map! do |error|
						if detail[errors.index(error)] == 0
							error = 'not defined'
						else
							error = error
						end
					end
					
					errors.each do |error| 
						unless error == 'not defined' 
							result += "#### #{error}\n"
						end
					end
					end
				end
			end
		end
		puts "sensor information meaning is #{result}"
		# result = result + "\n"
		return result
	end
	
	def decode_gts_detail(element, part)	
		result = String.new
		element = element.split("[ErrDspMgr.] ErrDspMgr: ")[1].strip
		puts "gts_detail found is #{element}"
		gts_divisions = @details["gts_detail_#{part}"].keys
		puts "gts_divisions are #{gts_divisions}"
		unless element == ("40" * 16)
			0.step(element.size - 1, 2) do |index|
				detail = (hex_to_bin element[index]) + (hex_to_bin element[index + 1])

				unless detail == [0,1,0,0,0,0,0,0]
					gts_division = gts_divisions[index / 2]
					puts gts_division
					
					result  = result +  "== #{gts_division}\n"
					
					unless /scrt/i.match gts_division
						errors = @details["gts_detail_#{part}"][gts_division]
						
						errors.map! do |error|
							if detail[errors.index(error)] == 0
								error = 'fixed'
							else
								error = error
							end
						end
					
						errors.each do |error| 
							unless error == 'fixed'
								puts error
								result = result + "#### #{error}\n"
							end
						end
					else
						u = 0
						t = detail[2,6].reverse
						t.each do |bit|
							u += bit * 2**(t.index(bit))
						end
							
						result  = result +  "#### #{u} communication errors occured\n"
					end
				end
			end
		end
		puts "=" * 100
		puts "the gts error sequence decoding resulted in #{result}"
		puts "=" * 100
		return result
	end
	
	def decode_lmudat (element, part)	
		result = String.new
		element = element.split("[ErrDspMgr.] ErrDspMgr: ")[1].strip
		puts "lmudat_detail found is #{element}"
		
		unless element == ("30" * 16)
			1.step(element.size - 1, 2) do |index|
				index2 = ((index -1 )/ 2) + 1
				detail = hex_to_bin element[index]
				unless detail == [0,0,0,0]
					errors = @details["lmudat_#{part}"][index2]
					
					errors.map! do |error|
						if detail[errors.index(error)] == 0
							error = 'not defined'
						else
							error = error
						end
					end
					
					errors.each do |error| 
						unless error == 'not defined' 
							result = result +  "#### #{error}\n"
						end
					end
				end
			end
			
			
			high_bits = hex_to_bin element[15]	#real position 8
			high_bits = high_bits[2, 3]
			low_bits = hex_to_bin element[13]	#real position 7

			id = high_bits + low_bits
			id = id.join
			id = convert_base(id, 2 ,10)
			id = id.to_i

			if ((id > 0) and (id < 39))
				result = result + "++++++++ Defective ADC is most likely located at slot #{id} ++++++++\n"
			elsif (id > 39)
				result = result + "++++++++ Several ADC's are considered defective.  Check led status of all ADC.  Do not remove DAS fans for more than 3 minutes. ++++++++\n"
			else
				''
			end
		end
		
		return result
	end
	
	def decode_xc_mode element
		result = String.new
		element = element.scan /\[\w\w\]/
		
		begin
			element[0] = element[0][1,2]
			element[1] = element[1][1,2]
		rescue
			element[0] = ''
			element[1] = ''
		end
		
		if /.R/.match element[0]
			result = result + "#### X-ray OFF (Ready)\n"
		elsif /.B/.match element[0]
			result = result + "#### X-ray ON (Busy)\n"
		elsif /.A/.match element[0]
			result  = result + "#### X-ray OFF that has occured as a result of exposure abort(Abort)\n"
		else
		end
		
		begin
			result  = result +  "#### " + @xc_cmd[element[1]] + "\n"
		rescue
		end
		
		return result
	end
	
	def decode_xc (element, type)
		element = element.split("[ErrDspMgr.] ErrDspMgr: ")[1].strip
		result = String.new
		puts "xc detail #{element} will be analyzed as #{type}"
		
		case type
			when 'xc' then xc_line_fine = "3f3f3f3f3f3f3f3f3f3f3f3f3f2f2f00"
				xc_bits_fine = [1,1,1,1]
				xc_bit_fine = 1
				start_bit = 1
			when 'xc2' then xc_line_fine = "40" * 16
				xc_bits_fine = [0,0,0,0]
				xc_bit_fine = 0
				start_bit = 1
			when 'xc3' then xc_line_fine = "40" * 16
				xc_bits_fine = [0,1,0,0,0,0,0,0]
				xc_bit_fine = 0
				start_bit = 0
		else
		end
		
		unless element == xc_line_fine
			start_bit.step(element.size - 1, 2) do |index|
				detail = hex_to_bin element[index]
				if type == 'xc3'
					detail1 = hex_to_bin element[index +1]
					detail = detail + detail1
					index2 = (index / 2) + 1
				else
					detail = detail.reverse
					index2 = ((index -1 )/ 2) + 1
				end
				
				unless detail == xc_bits_fine
					errors = @details[type][index2]
					
					errors.map! do |error|
						if detail[errors.index(error)] == xc_bit_fine
							error = 'not defined'
						else
							error = error
						end
					end
					
					errors.each do |error| 
						unless error == 'not defined' 
							result << "#### #{error}"
						end
					end
				end
			end
		end
		
		# feedback "used parse_xc" #, result is #{result}"
		return result
	end
	
	def convert_base (string, from, to)
		return string.to_i(from).to_s(to)
	end
	
	def hex_to_bin digit
		case digit
			when '0' then digit = [0,0,0,0]
			when '1' then digit = [0,0,0,1]
			when '2' then digit = [0,0,1,0]
			when '3' then digit = [0,0,1,1]
			when '4' then digit = [0,1,0,0]
			when '5' then digit = [0,1,0,1]
			when '6' then digit = [0,1,1,0] 
			when '7' then digit = [0,1,1,1]
			when '8' then digit = [1,0,0,0]
			when '9' then digit = [1,0,0,1]
			when 'a', 'A' then digit = [1,0,1,0]
			when 'b', 'B' then digit = [1,0,1,1]
			when 'c', 'C' then digit = [1,1,0,0]
			when 'd', 'D' then digit = [1,1,0,1]
			when 'e', 'E' then digit = [1,1,1,0]
			when 'f', 'F' then digit = [1,1,1,1]
		else
		end
	end
	
end



if __FILE__ == $0
	# puts "argv is -#{ARGV}-"
	unless (ARGV ==[])
		t1 = Time.now
		argus = Argus.new
	
		t2 = Time.now
		argus.find_eventlogs_by_date
		puts "#{Time.now - t2} elapsed"
	
		t2 = Time.now
		argus.eventlogs_to_txt
		puts "#{Time.now - t2} elapsed"
	
		puts "full process ran in #{Time.now - t1}"
		# system("explorer #{Dir.pwd.sub('bin', 'tmp').gsub('/', '\\') }")
	else 
		puts "ARGUS #{VERSION} is a standalone project developped in my spare time."
		puts "Hope you'll get some kicks out of it.  Willem Michiels"
		puts "\nUSAGE: argus cttype full"
		puts "\n\tcttype is one of the following:\n\n"
		t = YAML.load(File.open("../etc/ct_type.yaml", 'r'))
		t.each_pair do |key, value| 
			puts "\t\t#{value}\t#{key}"
		end
		puts "\n\tfull \tis an optional feature and will keep more information such as\n\t\tscan parameters, recon parameters, couch movement."	
		puts "\n\tresult will be stored in the summary directory"
	end
end