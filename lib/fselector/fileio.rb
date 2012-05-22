#
# read and write various file formats, 
# the internal data structure looks like:  
#      
#     data = {
#     
#       :c1 => [                             # class c1
#         {:f1=>1, :f2=>2}                   # sample 2
#       ],
#       
#       :c2 => [                             # class c2
#         {:f1=>1, :f3=>3},                  # sample 1
#         {:f2=>2}                           # sample 3
#       ]
#       
#     }
#     
#     where :c1 and :c2 are class labels; :f1, :f2, and :f3 are features
#
# @note class labels and features are treated as symbols
#
module FileIO
  # require the open-uri lib for http/https/ftp request
  require 'open-uri'
  # require the stringio lib for converting a string into stringio object
  require 'stringio'
  
  #
  # read from random data (read only, for test purpose)
  #
  # @param [Integer] nsample number of total samples
  # @param [Integer] nclass number of classes
  # @param [Integer] nfeature number of features
  # @param [Integer] ncategory number of categories for each feature  
  #   1      # binary feature with only on bit  
  #   >1     # discrete feature with multiple values  
  #   other  # continuous feature with vaule in the range of [0, 1)
  # @param [true, false] allow_mv whether missing value of feature is alowed or not
  #
  def data_from_random(nsample=100, nclass=2, nfeature=10, ncategory=2, allow_mv=true)
    data = {}
  
    nsample.times do
      k = "c#{rand(nclass)+1}".to_sym
      
      data[k] ||= []
      
      feats = {}
      fs = (1..nfeature).to_a
      
      if allow_mv
        (rand(nfeature)).times do
          v = fs[rand(fs.size)]
          fs.delete(v)
        end
      end
      
      fs.sort.each do |i|
        f = "f#{i}".to_sym
        if ncategory == 1
          feats[f] = 1
        elsif ncategory > 1
          feats[f] = rand(ncategory)+1
        else
          feats[f] = rand.round(3) # round to 3-digit precision
        end
      end
      
      data[k] << feats
    end

    set_data(data)
  end # data_from_random
  
  
  #
  # read from libsvm
  #
  # file has the following format  
  # +1  2:1 4:1 ...  
  # -1  3:1 4:1 ...  
  # ....
  #
  # @param [Symbol|String|StringIO] fname data source to read from  
  #   :stdin  # read from standard input instead of file
  #
  def data_from_libsvm(fname=:stdin)    
    ifs = get_ifs(fname)
    
    data = {}
    
    ifs.each_line do |ln|
      label, *features = ln.chomp.split(/\s+/)
      label = label.to_sym
      data[label] ||= []
      
      feats = {}
      features.each do |fv|
        f, v = fv.split(/:/)
        feats[f.to_sym] = v.to_f
      end
      
      data[label] << feats
    end
    
    # close file
    ifs.close if not ifs == $stdin
    
    set_data(data)
  end # data_from_libsvm
  
  
  #
  # write to libsvm
  #
  # @param [String] fname file to write  
  #   :stdout  # write to standard ouput
  #
  def data_to_libsvm(fname=:stdout)
    ofs = get_ofs(fname)
    
    # convert class label to integer type
    k2idx = {}
    get_classes.each_with_index do |k, i|
      k2idx[k] = i+1
    end
    
    # convert feature to integer type
    f2idx = {}
    get_features.each_with_index do |f, i|
      f2idx[f] = i+1
    end
    
    each_sample do |k, s|
      ofs.print "#{k2idx[k]} "
      s.keys.sort { |x, y| f2idx[x] <=> f2idx[y] }.each do |f|
        ofs.print " #{f2idx[f]}:#{s[f]}" if not s[f].zero? # implicit mode
      end
      ofs.puts
    end
    
    # close file
    ofs.close if not ofs == $stdout
  end # data_to_libsvm
  
  
  #
  # read from csv
  #
  # if no csv_opts supplied, we assume the CSV file in the following format:  
  # first and second rows contain feature names and types, respectively. 
  # 
  #     feat_name1,feat_name2,...,feat_namen  
  #     feat_type1,feat_type2,...,feat_typen  
  # 
  # and the remaing rows containing the data with first column being the class label 
  #
  #     class_label,feat_value1,feat_value2,...,feat_value3  
  #     ...  
  # 
  # allowed feature types (case-insensitive) are:  
  # INTEGER, REAL, NUMERIC, CONTINUOUS, STRING, NOMINAL, CATEGORICAL
  #
  # @param [Symbol|String|StringIO] fname data source to read from  
  #   :stdin  # read from standard input
  # @param [Hash] csv_opts named arguments for csv options     
  #   :feature\_name\_row => 1,    # row that contains feature names  
  #   :feature\_type\_row => 2,    # row that contains feature types  
  #   :feature\_name2type => {},   # a user-supplied hash containing feature name-type pairs 
  #                                  if no rows specify them. feature must be in the same order 
  #                                  as it appears in the dataset  
  #   :class\_label\_column  => 1  # column that contains class labels
  #
  # @note missing values are allowed
  #
  def data_from_csv(fname=:stdin, csv_opts = {})
    ifs = get_ifs(fname)
    
    opts = { # default options, new opts will override old ones
      :feature_name_row => 1,    # first row contains feature names
      :feature_type_row => 2,    # second row contains feature types
      :feature_name2type => {},  # user-supplied feature name-type pairs
      :class_label_column => 1,  # first column contains class labels
    }
    opts.merge!(csv_opts) if csv_opts and csv_opts.class == Hash
    
    feature_name_row = opts[:feature_name_row]
    feature_type_row = opts[:feature_type_row]
    feature_name2type = opts[:feature_name2type]
    class_label_column = opts[:class_label_column]
    
    # user-supplied feature name-type pairs, this is useful 
    # when file contains no specific rows for feture names and types
    if feature_name2type and not feature_name2type.empty?
      features = feature_name2type.keys.collect { |n| n.to_sym }
      types = feature_name2type.values.collect { |t| t.downcase.to_sym }
      # disable name and type rows
      feature_name_row, feature_type_row = nil, nil
    end
    
    data = {}
    
    ifs.each_line do |ln|
      next if ln.blank?
      
      if ifs.lineno == feature_name_row # feature names
        features = ln.chomp.split(/,/).to_sym
      elsif ifs.lineno == feature_type_row # second types
        # store feature type as lower-case symbol
        types = ln.chomp.split(/,/).collect { |t| t.downcase.to_sym }
      else # data rows
        cells = ln.chomp.split(/,/)
        
        if class_label_column <= cells.size
          label = cells[class_label_column-1]
          label = label.to_sym
          data[label] ||= []
          
          # remove class label
          cells.delete_at(class_label_column-1)
          fvs = cells
        else
          abort "[#{__FILE__}@#{__LINE__}]: \n"+
                "  the class label column can't found!"
        end              
        
        fs = {}
        fvs.each_with_index do |v, i|
          next if v.empty? # missing value
          feat_type = types[i]
          if feat_type == :integer
            v = v.to_i
          elsif [:real, :numeric, :continuous].include? feat_type
            v = v.to_f
          elsif [:string, :nominal, :categorical].include? feat_type
            #
          else
            abort "[#{__FILE__}@#{__LINE__}]: \n"+
                  "  invalid feature type!"
          end
          
          fs[features[i]] = v
        end
        
        data[label] << fs
      end
    end
    
    # close file
    ifs.close if not ifs == $stdin
    
    set_data(data)
    set_features(features)
    
    # feature name-type pairs
    name2type = {}
    features.each_with_index do |f, i|
      name2type[f] = types[i]
    end
    set_opt(:feature_type, name2type)
  end # data_from_csv
  
  
  #
  # write to csv
  #
  # file has the format with the first two rows
  # specifying features and their data types
  # and the remaing rows showing data
  #
  # @param [String] fname file to write  
  #   :stdout  # write to standard ouput
  #
  def data_to_csv(fname=:stdout)
    ofs = get_ofs(fname)
    
    # feature names 
    ofs.puts get_features.join(',')
    # feature types
    ofs.puts get_features.collect { |f| 
      get_feature_types(f) || :string
    }.join(',')
    
    each_sample do |k, s|
      ofs.print "#{k}"
      each_feature do |f|
        if s.has_key? f
          ofs.print ",#{s[f]}"
        else
          ofs.print ","
        end
      end
      ofs.puts
    end
    
    # close file
    ofs.close if not ofs == $stdout
  end # data_to_csv
  
  
  #
  # read from WEKA ARFF file
  #
  # @param [Symbol|String|StringIO] fname data source to read from  
  #   :stdin  # read from standard input
  # @note it's ok if string containes spaces quoted by quote_char
  #
  def data_from_weka(fname=:stdin, quote_char='"')
    ifs = get_ifs(fname)
    
    relation, features, classes, types, comments = '', [], [], [], []
    has_class, has_data = false, false
    
    data = {}
    
    ifs.each_line do |ln|
      next if ln.blank? # blank lines
      
      ln = ln.chomp
      
      # comment line
      if ln.comment?('%')
        comments << ln
      # relation
      elsif ln =~ /^@RELATION/i
        tmp, relation = ln.split_me(/\s+/, quote_char)
      # class attribute
      elsif ln =~ /^@ATTRIBUTE\s+class\s+{(.+)}/i
        has_class = true
        classes = $1.strip.split_me(/,\s*/, quote_char).to_sym
        classes.each { |k| data[k] = [] }
      # feature attribute (nominal)
      elsif ln =~ /^@ATTRIBUTE\s+(\S+)\s+{(.+)}/i
        f = $1.to_sym
        features << f
        #$2.split_me(/,\s*/, quote_char) # feature nominal values
        types << :nominal
      # feature attribute (integer, real, numeric, string, date)
      elsif ln =~ /^@ATTRIBUTE/i
        tmp, v1, v2 = ln.split_me(/\s+/, quote_char)
        f = v1.to_sym
        features << f
        # store feture type as lower-case symbol
        types << v2.downcase.to_sym
      # data header
      elsif ln =~ /^@DATA/i
        has_data = true
      # data
      elsif has_data and has_class
        # read data section
        if ln =~ /^{(.+)}$/ # sparse ARFF
          feats = $1.split_me(/,\s*/, quote_char)
          label = feats.pop.split_me(/\s+/, quote_char)[1]
          label = label.to_sym
          
          fs = {}
          # indices of feature with zero value
          zero_fi = (0...features.size).to_a
          
          feats.each do |fi_fv|
            fi, fv = fi_fv.split_me(/\s+/, quote_char)
            fi = fi.to_i             
            add_feature_weka(fs, features[fi], fv, types[fi])
            zero_fi.delete(fi)
          end
          
          # feature with zero value
          zero_fi.each do |zi|
            add_feature_weka(fs, features[zi], 0, types[zi])
          end
          
          data[label] << fs
        else # regular ARFF
          feats = ln.split_me(/,\s*/, quote_char)
          label = feats.pop.to_sym          
          
          fs = {}
          feats.each_with_index do |fv, i|
            add_feature_weka(fs, features[i], fv, types[i])
          end
          data[label] << fs if label
        end
      else
        next
      end
    end
    
    # close file
    ifs.close if not ifs == $stdin
    
    set_data(data)
    set_classes(classes)
    set_features(features)
    set_opt(:relation, relation)
    
    # feature name-type pairs
    name2type = {}
    features.each_with_index do |f, i|
      name2type[f] =  types[i]
    end
    set_opt(:feature_type, name2type)
    
    set_opt(:comments, comments) if not comments.empty?
  end # data_from_weak
  
  
  #
  # write to WEKA ARFF file
  #
  # @param [String] fname file to write  
  #   :stdout  # write to standard ouput
  # @param [Symbol] format sparse or regular ARFF  
  #   :sparse  # sparse ARFF, otherwise regular ARFF
  #
  def data_to_weka(fname=:stdout, format=nil)
    ofs = get_ofs(fname)
    
    # comments
    comments = get_opt(:comments)
    if comments
      ofs.puts comments.join("\n")
      ofs.puts
    end         
    
    # relation
    relation = get_opt(:relation)
    if relation
      ofs.puts "@RELATION #{relation}"
    else
      ofs.puts "@RELATION data_gen_by_FSelector"
    end
    
    ofs.puts
    
    # feature attribute
    each_feature do |f|
      ofs.print "@ATTRIBUTE #{f} "
      type = get_feature_types(f)
      if type
        if type == :nominal
          ofs.puts "{#{get_feature_values(f).uniq.sort.join(',')}}"
        else
          ofs.puts type
        end
      else # treat all other feature types as string
        ofs.puts :string
      end
    end
    
    # class attribute
    ofs.puts "@ATTRIBUTE class {#{get_classes.join(',')}}"
    
    ofs.puts
    
    # data header
    ofs.puts "@DATA"
    each_sample do |k, s|
      if format == :sparse # sparse ARFF
        ofs.print "{"
        get_features.each_with_index do |f, i|
          if s.has_key? f
            ofs.print "#{i} #{s[f]}," if not s[f].zero?
          else # missing value
            ofs.print "#{i} ?,"
          end
        end
        ofs.print "#{get_features.size} #{k}"
        ofs.puts "}"
      else # regular ARFF
        each_feature do |f|
          if s.has_key? f
            ofs.print "#{s[f]},"
          else # missing value
            ofs.print "?,"
          end
        end
        ofs.puts "#{k}"
      end
    end
    
    # close file
    ofs.close if not ofs == $stdout
  end # data_to_weka
  
  
  # read data from url
  #
  # @param [String] url url of on-line dataset
  # @param [Symbol] format allowed formats are:  
  #   :libsvm  # LibSVM file  
  #   :csv     # csv file  
  #   :weka    # Weka ARFF file
  # @param [Any] args arguments associated with format
  #
  def data_from_url(url, format, *args)
    format = format.downcase.to_sym
    
    if not [:libsvm, :csv, :weka].include? format
      abort "[#{__FILE__}@#{__LINE__}]: \n"+
            "  only CSV, LibSVM and Weka file formats are supported!"
    end
    
    uri = URI.parse(URI.encode(url))
    
    data_src = StringIO.new(uri.read)
    
    if format == :csv
      data_from_csv(data_src, *args)
    elsif format == :libsvm
      data_from_libsvm(data_src)
    else # weka
      data_from_weka(data_src, *args)
    end
  end # data_from_url
  
  private
  
  # get the input file handler
  def get_ifs(fname)
    # read from standard input by default
    if fname == :stdin
      ifs = $stdin
    # read from string if it is a StringIO
    elsif fname.class == StringIO
      ifs = fname
    # read from file if file exists
    elsif File.exists? fname
      ifs = File.open(fname)
    else
      abort "[#{__FILE__}@#{__LINE__}]: \n"+
            "  invalid data source!"
    end
    
    ifs
  end
  
  
  # get the ouput file handler
  def get_ofs(fname)
    if fname == :stdout
      ofs = $stdout
    else
      ofs = File.open(fname, 'w')
    end
    
    ofs
  end
  
  
  # handle and add each feature for WEKA format
  #
  # @param [Hash] fs sample that stores feature and its value
  # @param [Symbol] f feature
  # @param [String] v feature value
  # @param [Symbol] type feature type
  #
  def add_feature_weka(fs, f, v, type)
    if v == '?' # missing value
      return
    elsif type == :integer
      fs[f] = v.to_i
    elsif type == :real or type == :numeric
      fs[f] = v.to_f
    elsif type == :string or type == :nominal
      fs[f] = v
    elsif type == :date # convert into integer
      fs[f] = (DateTime.parse(v)-DateTime.new(1970,1,1)).to_i
    else
       return
    end
  end # add_feature_weka
     
 
end # module
