class Ruby_gems
	def initialize
		@log = $log
		@rpm_download_site = 'magic-beans.org'
		@SLES11_i586_rpm_dir = '/conserve/additional_rpms/SLES11/i586'
		@SLES11_i586_rpms = ['ruby-1.8.7.p352-1.1.i586.rpm', 'ruby-devel-1.8.7.p352-1.1.i586.rpm', 'rubygems-1.3.7-10.1.i586.rpm']
	end
	
	def install_rubygems
		answer = nil
		while answer != 'y' && answer != 'n' do
			print "\t\tWould you like to install \"ruby gem\" utility from ftp://#{@rpm_download_site}? [y|n]: "
			answer = $stdin.gets.chomp
		end
		if answer == 'n'
			raise "Inform aborded"
		else
			begin
				download_dir = "/tmp/ruby_rpms_temp"
				Dir.mkdir(download_dir)
				Dir.chdir(download_dir)
				get_rubygems_rpms
				install_rubygems_rpms
			ensure
				Dir.entries(download_dir).each{|file|
					File.unlink(file) if file != '.' && file != '..'
				}
				Dir.unlink(download_dir)
				Dir.chdir
			end
		end
	end
	
	def check_rubygems
		gem = `which gem 2>/dev/null`.chomp
		gem == '' ? false : gem
	end
	
	def gem_installed?(gem)
		gem_cmd = check_rubygems
		if gem_cmd
			`#{gem_cmd} list #{gem}`.index('mail') ? true : false
		end
	end
	
	def install_mail_gem
		answer = nil
		while answer != 'y' && answer != 'n' do
			print "\t\tWould you like to install \"mail\" ruby gem? [y|n]: "
			answer = $stdin.gets.chomp
		end
		if answer == 'n'
			raise "Inform aborded"
		else
			install_gem('mail')
		end
	end

###########
	private
###########
	
	def detect_os
		rel_file = nil
		Dir.entries('/etc').each{|file|
			rel_file = file if /-release/ =~ file
		}
		rel_info = IO.read("/etc/#{rel_file}")
		rel_info = s_to_a(rel_info)
		if rel_info[0].index('SUSE Linux Enterprise Server 11')
			os = 'SLES11' if rel_info[2].chomp == 'PATCHLEVEL = 0'
			os = 'SLES11 sp.1' if rel_info[2].chomp == 'PATCHLEVEL = 1'
			arch = ((rel_info[0].split('('))[1].split(')'))[0]
		elsif rel_info[0] == 'DISTRIB_ID=Ubuntu'
			os = 'Ubuntu'
			arch = nil
		end
		result = [os, arch]
	end
	
	def install_gem(gem)
		gem_cmd = check_rubygems
		if gem_cmd
			@log.write("\t\t\tInstalling ruby gem \"#{gem}\"...")
			`#{gem_cmd} install #{gem}`
		else
			raise "Failed to find \"ruby gem\" utility"
		end
	end
	
	def	get_rubygems_rpms
		begin
			# use net/ftp
			require 'net/ftp'
			ftp = Net::FTP.new
			ftp.connect(@rpm_download_site,21)
			ftp.login('anonymous', '1212121212')
			# detect OS and arch to understand what rpms to download
			os = detect_os
			if (os[0] == 'SLES11' || os[0] == 'SLES11 sp.1')
				@log.write("\t\t\t#{os[0]} with #{os[1]} architecture detected.")
				ftp.chdir(@SLES11_i586_rpm_dir) if os[1] == 'i586'
			else
				raise "Don't have FTP directory for \"#{os[0]}\" #{os[1]}"
			end
			@SLES11_i586_rpms.each{|file|
				@log.write("\t\t\tDownloading #{file} from #{@rpm_download_site}...")
				ftp.getbinaryfile(file,"./#{file}")
			}
		rescue LoadError
			# use wget
			raise "NEED TO WRITE FTP DOWNLOAD WITH \"WGET\""
		rescue RuntimeError
			raise "FTP download failed: #{$!}"
		rescue
			raise "FTP download failed: #{$!}"
		ensure
			ftp.close
		end
	end
	
	def install_rubygems_rpms
		Dir.entries(Dir.pwd).each{|file| 
			if /ruby-\d/ =~ file
				@log.write("\t\t\tUpgrading ruby by #{file}...")
				`rpm -U #{file} 2>/dev/null`
			end
		}
		Dir.entries(Dir.pwd).each{|file|
			if /ruby-devel-\d/ =~ file
				@log.write("\t\t\tInstalling #{file}...")
				`rpm -i #{file} 2>/dev/null`
			end
		}
		Dir.entries(Dir.pwd).each{|file|
			if /rubygems-\d/ =~ file
				@log.write("\t\t\tInstalling #{file}...")
				`rpm -i #{file} 2>/dev/null`
			end
		}
	end
end
