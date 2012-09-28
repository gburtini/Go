#!/usr/bin/env ruby
require 'optparse'

DEFAULT_NAME = File.expand_path "~/.go.data"
LEVENTHRESHOLD = 10
DEFAULT_EDITOR = "vim"

def printVerbose(string) 
	if ($options[:verbose] or $options[:extra_verbose]) then
		$stderr.puts string
	end
end

def printExtraVerbose(string)
	if($options[:extra_verbose]) then
		$stderr.puts string
	end
end

L_ADD_COST = 1
L_DEL_COST = 1
L_SUB_COST = 1
def levenshtein(a, b)
	back = nil, back2 = nil
	current = (1..b.size).to_a + [0]
	a.size.times do |x|
		# shuffle previous three steps and create a new one for this round
		back2, back, current = back, current, [0] * b.size + [x + 1]

		b.size.times do |y|
			# compute the different ways we could get there.
			del = back[y] + L_DEL_COST
			add = current[y - 1] + L_ADD_COST
			sub = back[y - 1] + ((a[x] != b[y]) ? L_SUB_COST : 0)
			current[y] = [del, add, sub].min

			if (x > 0 && y > 0 && a[x] == b[y-1] && a[x-1] == b[y] && a[x] != b[y])
				current[y] = [current[y], back2[y-2] + 1].min
			end
		end
	end
	
	return current[b.size - 1]
end

# invokes $EDITOR on the file. if the file doesn't exist, creates it and puts a comment at the top.
def editFile(file)
	if ( ! File.exists?(file)) then
		fh = File.new(file, File::CREAT|File::TRUNC|File::RDWR);
		fh.write("# Put entries below here with [slug | path | title]");
		fh.close
	end

	printVerbose("Starting editor on " + file)
	
	if (ENV.key?("EDITOR"))  then
		system( ENV['EDITOR'] + ' ' + file )
	else
		system( DEFAULT_EDITOR + ' ' + file )
	end
	puts "Database file " + file + " updated.\n"
	Process.exit
end

# prints a list of all the values in the database
def listEntries(file) 
	printVerbose("Listing entries in " + file)
	list = File.open(file).readlines

	printVerbose("Found " + list.count.to_s + " lines.")
	list.each do |entry|
		if !(/^\s*[#%]/.match(entry) || /^$/.match(entry)) then
			values = entry.split(/\|/).map do |value|
				value.strip!
			end
			
			if (values != nil) then
				if (values[3] != nil) then
					values[1] = "ssh " + values[1]
				end
				puts values[0] + " - " + values[2].to_s + " (" + values[1] + ")"
			end
		end
	end
end

# searches the file for the first match in the searches array.
def searchEntries(file, searches)
	printVerbose("Searching the entries in " + file)

        if File.exists?(file)
                list = File.open(file).readlines
		list.reject! { |c| c.strip.empty? }
        else
		printVerbose("File did not exist. Creating it.")
                editFile(file)
        end

	
	prediction = {}
        searches.each do |search|
		printExtraVerbose("Searching for string " + search)
                list.each do |v|
			printExtraVerbose("Checking row " + v)
			# TODO: validate row here.

			mode = :directory
			
                        values = v.split(/\|/).map do |a|
				a.strip!
			end
			lev = levenshtein(search, values[0])
			if (prediction[values[0]] == nil || lev < prediction[values[0]]) then
				prediction[values[0]] = lev
			end

			if(values.count > 3 and values[3] == "ssh") then
				mode = :ssh
			end

                        if (values[0] == search)
				case mode
					when :directory
						printVerbose("Found " + search + " -- executing.")
		                                puts values[2] + " ==> Changing directory to " + values[1]
                		                Dir.chdir(File.expand_path values[1])	# output the actual path for the bash script to redirect.
						exec 'bash'

					when :ssh
						exec 'bash -c "ssh" ' + values[1]
				end

				Process.exit
                        end
                end
        end

	# if we get down here, we didn't find anything.
	prediction = prediction.sort_by{|key,value| value}
	iterator = $options[:suggest]
	
	recommendations = "";
	while(iterator > 0) do
		predicted = prediction.shift
		if (predicted == nil) then
			iterator = 0
		else 
			if ($options[:suggest] > 1 || predicted[1] < LEVENTHRESHOLD) then
				recommendations += "'" + predicted[0] + "', "
			else
				iterator = 0
			end
		end
		iterator -= 1
	end

	recommendations.chomp!(", ")
	
	if(recommendations.length > 0) then
		if ($options[:suggest] > 1) then
			puts "No command found. Did you mean one of the following?"
			puts recommendations
		else
			puts "No command found. Did you mean " + recommendations + "?" 
		end
	end
end
	

$options = {}
opts = OptionParser.new do |opts|
	opts.banner = "Usage: go [-l] [-e] [-w] [-v] [-s] [-h] [-d db_path] [slug]"
	$options[:verbose] = false;
	$options[:extra_verbose] = false;
	opts.on('-v', '--verbose', "Output more information.") do
		$options[:verbose] = true
	end
	opts.on('-w', '--extra-verbose', "Output even more information.") do
		$options[:extra_verbose] = true
	end
	

	$options[:db_path] = DEFAULT_NAME
	opts.on('-d', '--database-path FILE', 'Specify an alternative database. By default, /var/go.data.') do |val|
		$options[:db_path] = val
	end

	$options[:mode] = :search
	opts.on('-e', '--edit', 'Edit the database.') do 
		$options[:mode] = :edit
	end

	opts.on('-l', '--list', 'List the database.') do 
		$options[:mode] = :list
	end
	$options[:suggest] = 1
	opts.on('-s', '--suggest', 'Suggest best matches.') do 
		$options[:suggest] = 10
	end

	opts.on_tail( '-h', '--help', 'Display this screen.' ) do
     		puts opts
   		Process.exit
	end
end
opts.parse!

case $options[:mode]
	when :edit
		editFile($options[:db_path])
	when :list
		listEntries($options[:db_path])
	else	# when :search
		if(ARGV.count > 0) then
			searchEntries($options[:db_path], ARGV)
		else
			puts opts
		end
end

