class Log

	attr_accessor :log_file, :log_enabled, :start_time
	
	def initialize()
		@log_file = nil
		@log_enabled = false
		@start_time = nil
		@skip_time = false
	end
	
	def write(info)
		if @log_enabled == true
			to_log(info, "\n")
		else
			to_stdout(info, "\n")
		end
	end
	
	def write_noel(info)
		if @log_enabled == true
			to_log(info, '')
			@skip_time = true
		else
			to_stdout(info, '')
			$stdout.flush
		end
	end

	def to_stdout(info,el)
		print info + el
	end
	
	def to_log(info, el)
		begin
			File.open(@log_file, "a"){ |openfile|
					@start_time = Time.now.asctime
					if @skip_time == true
						openfile.print "#{info}#{el}"
						@skip_time = false
					else
						openfile.print "#{@start_time} - #{info}#{el}"
					end
				}
			status = 0
			error = nil
		rescue
			status = 1
			error = $!
		end
		result = [status, error]
	end
	
	
end
