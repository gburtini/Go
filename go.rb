#!/usr/bin/env ruby
###	Go.rb - a command line bookmarks/navigation tool
###		by Giuseppe Burtini <joe@truephp.com>
###	
###	Run go.rb -h for quick synopsis. Go allows you to navigate between directories or ssh servers
###	by using short slugs. Run go.rb -e to edit the database of slugs, go -l to see the available
###	database and go [slug] to actually perform a navigation. 
###
###	The database file is stored by default in ~/.go.data. If you run go without a valid database file
###	it will automagically create one. Just a heads up, so that we don't pollute your ~ without telling you. 
###
###	TODO: 	change the database format to something reasonable... a B+-tree can reflect the data efficiently.
###		although it is definitely overkill, considering the reasonable size of the database.
###	TODO: 	autocomplete interface with bash.

require 'optparse'

# the default database file (this can be overridden with --database-path/-d)
DEFAULT_NAME = File.expand_path "~/.go.data"

# the maximum Levenshtein threshold (this can be overridden with --suggest/-s)
LEVENTHRESHOLD = 20

# the default text editor, for editing the database file. this will only be used if $EDITOR isn't set
DEFAULT_EDITOR = "vi"

# the default shell to be launched. this will only be used if $SHELL isn't set.
DEFAULT_SHELL = "bash"

def terminalSize() 
	return `stty size`.split.map { |x| x.to_i }.reverse 
end

def printVerbose(string) 
	if ($options[:verbose] or $options[:extra_verbose]) then
		$stderr.puts string
	end
end

def printExtraVerbose(string)
	if ($options[:extra_verbose]) then
		$stderr.puts string
	end
end

# associated Levenshtein costs.
L_ADD_COST = 2
L_DEL_COST = 3
L_SUB_COST = 2 
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

def prefixCount(a, b)
        a, b = a.split(""), b.split("")
        a.length.times do |index|
                if(a[index] != b[index]) then
                        return index
                end
        end

        return a.length
end

def validateFile(file)
	if ( ! File.exists?(file)) then
		fh = File.new(file, File::CREAT|File::TRUNC|File::RDWR);
		fh.puts("# Put entries below here with [slug | path | title [| binary]]");
		fh.puts("# If you specify a fourth parameter, path is treated as arguments to binary.")
		fh.close
	end
end

def readFile(file) 
	list = File.open(file).readlines
	list.reject! { |c| c.strip.empty? }		# remove anything that's just whitespace.
	list.reject! { |c| (/^\s*[#%]/.match(c)) } 	# remove comments.
	return list
end

def addRecord(file, arguments) 
	validateFile(file)

	# TODO: this needs to take arbitrary (optional) number of arguments 
	# -and- needs to check for duplicate paths (add comma delimited instead
	# of duplicate records)
	# TODO: check for duplicate keys.
	# TODO: validate input.
	# TODO: support ssh
	# TODO: when adding an ssh connection, make it add the ssh key.

	key = arguments[0]
	path = Dir.pwd
	message = arguments[1]
	fh = File.open(file, "a");
	fh.puts(key + " | " + path + " | " + message + "")
	fh.close
end

# invokes $EDITOR on the file. if the file doesn't exist, creates it and puts a comment at the top.
def editFile(file)
	validateFile(file)

	printVerbose("Starting editor on " + file)
	
	if (ENV.key?('EDITOR'))  then
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
	list = readFile(file)

	# terminal width, minus the templating characters. 
	templating_width = 10
	columns = terminalSize()[0] - templating_width
	key_width = (columns / 3).floor - 5;
	description_width = (columns / 3).ceil + 5
	path_width = (columns / 3).floor

	printVerbose("Found " + list.count.to_s + " lines.")
	puts "  Keys / Search Terms".ljust(key_width) +
		"   " + "Description".rjust(description_width) + 
		" => " + "Path / Action".ljust(path_width)

	puts "=" * (columns+templating_width)
	list.each do |entry|
		values = entry.split(/\|/).map do |value|
			value.strip!
		end
			
		if (values != nil) then
			if (values[3] != nil) then
				values[1] = values[3] + " " + values[1]
			end

			puts "| " + (values[0].gsub(",", ", ")).ljust(key_width) + 
				" | " + values[2].to_s.rjust(description_width) + 
				" => " + values[1].ljust(path_width) + " |"
		end
	end
	puts "=" * (columns+templating_width)
end

# searches the file for the first match in the searches array.
def searchEntries(file, searches)
	printVerbose("Searching the entries in " + file)

        if File.exists?(file)
        	list = readFile(file)
	else
		printVerbose("File did not exist. Creating it.")
                editFile(file)
        end

	
	lev_prediction = {}
	pc_prediction = {}

	searches = [searches] if not searches.kind_of?(Array)

        searches.each do |search|
		printExtraVerbose("Searching for string " + search)
                list.each do |v|
			printExtraVerbose("Checking row " + v)
			# TODO: validate row here.

			mode = :directory
			
                        values = v.split("|").map do |a|
				a.strip!
			end

			# allow comma delimited keys (to allow multiple search strings for one row)
			values[0].split(",").each do |testvalue|
				lev = levenshtein(search, testvalue) / testvalue.length
				pc = prefixCount(testvalue, search)

				if (lev_prediction[testvalue] == nil || lev < lev_prediction[testvalue]) then
					lev_prediction[testvalue] = lev
				end
				if (pc_prediction[testvalue] == nil || pc > pc_prediction[testvalue]) then
					pc_prediction[testvalue] = pc
				end

                        	if (testvalue == search)
					if (values.count > 3 and values[3] == "ssh") then
						mode = :ssh
					elsif (values.count > 3) then
						mode = :exec
					end

					if (ENV.key?( 'SHELL' )) then
						shell = ENV['SHELL']
					else
						shell = DEFAULT_SHELL
					end
					
					case mode
						when :directory
							printVerbose("Found " + search + " -- executing.")
			                                puts values[2] + " ==> Changing directory to " + values[1]
        	        		                Dir.chdir(File.expand_path values[1])	# output the actual path for the bash script to redirect.
							exec shell
	
						when :ssh
							exec shell + ' -c "ssh ' + values[1] + '"'
						when :exec
							exec shell + ' -c "' + values[3] + ' ' + values[1] + '"'
					end

					Process.exit
	                        end	
			end
                end
        end

	# check for unique prefix matches
	pc_prediction = pc_prediction.sort_by{|key,value| value}.reverse
	first, second = pc_prediction.shift, pc_prediction.shift
	
	if (first[1] != second[1] and first[1] != 0) then	# top two results have different values
		puts "You must have meant " + first[0] + ". Going there now."
		searchEntries(file, first[0])
	end

	# if we get down here, we didn't find anything.
	# output the Levenshtein suggestions!
	prediction = lev_prediction.sort_by{|key,value| value}
	iterator = $options[:suggest]
	
	recommendations = "";	# accumulator for the list of suggestions
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

	# print out the suggestions...
	if (recommendations.length > 0) then
		if ($options[:suggest] > 1) then
			puts "No command found. Did you mean one of the following?"
			puts recommendations
		else
			puts "No command found. Did you mean " + recommendations + "?"
			print "y/[n]: "
			input = STDIN.gets.chomp.downcase
			if (input == "y" || input == "yes") then
				searchEntries(file, recommendations.gsub(/^\'|\'$/, ""));		
			end	
		end
	end
end
	


# int main() { 
$options = {}
opts = OptionParser.new do |opts|
	opts.banner = "Usage: go [-a] [-l] [-e] [-w] [-v] [-s] [-h] [-d db_path] [slug]"
	
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

	opts.on('-a', '--add', 'Add record to the database.') do 
		$options[:mode] = :add
	end

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

# determine what to actually do, based on the options passed. by default, call searchEntries.
case $options[:mode]
	when :add
		addRecord($options[:db_path], ARGV)
	when :edit
		editFile($options[:db_path])
	when :list
		listEntries($options[:db_path])
	else	# when :search
		if (ARGV.count > 0) then
			searchEntries($options[:db_path], ARGV)
		else
			puts opts
		end
end
# } 

