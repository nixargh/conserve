#Conserve - linux backup tool.
#Copyright (C) 2013  nixargh <nixargh@gmail.com>
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see http://www.gnu.org/licenses/gpl.html.
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
			@log.write_noel("\t\tWould you like to install \"ruby gem\" utility? [y|n]: ", 'sky_blue', true)
			answer = $stdin.gets.chomp
		end
		if answer == 'n'
			raise "Inform aborded"
		else
			begin
				os = detect_os[0]
				if os == 'Ubuntu'
					`apt-get update`
					`apt-get -y install rubygems`
				elsif os == 'CentOS'
					`yum -y install rubygems`
				elsif os.index('SLES11')
					while answer != 'y' && answer != 'n' do
						@log.write_noel("\t\t\tInstall it from ftp://#{@rpm_download_site}? [y|n]: ", 'sky_blue', true)
						answer = $stdin.gets.chomp
					end
					if answer == 'n'
			                        raise "Inform aborded"
					else
						download_dir = "/tmp/ruby_rpms_temp"
						Dir.mkdir(download_dir)
						Dir.chdir(download_dir)
						get_rubygems_rpms
						install_rubygems_rpms
					end
				else
					raise 'Don\'t know how to install ruby gem package for your OS. Please do it manually and rerun this job'
				end
			ensure
				if download_dir
					Dir.entries(download_dir).each{|file|
						File.unlink(file) if file != '.' && file != '..'
					}
					Dir.unlink(download_dir)
					Dir.chdir
				end
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
			@log.write_noel("\t\tWould you like to install \"mail\" ruby gem? [y|n]: ", 'sky_blue', true)
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
		elsif rel_info[0].index('CentOS')
			os = 'CentOS'
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
