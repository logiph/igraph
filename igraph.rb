#! /usr/bin/ruby
require 'pathname'
require 'tempfile'

########################################################################################################################
# 存放一些结果的全局变量
$output_dir = "output"
$intermediate_dir = "intermediate"
$symbols_dir = "symbols"
$output_symbols_dir = "output/symbols"

########################################################################################################################

# 重新解析符号的内容，逆向编译符号编码，生成唯一的符号格式
def parse_symbol(symbol)

    # 分策略来解析
    keywords = ["_OBJC_CLASS_$_",
                "_OBJC_METACLASS_$_",
                "_OBJC_IVAR_$_",
                "l_OBJC_$_CLASS_METHODS_",
                "l_OBJC_$_INSTANCE_METHODS_",
                "l_OBJC_$_INSTANCE_VARIABLES_",
                "l_OBJC_$_PROTOCOL_REFS_",
                "l_OBJC_$_PROTOCOL_METHOD_TYPES_",
                "l_OBJC_$_PROTOCOL_INSTANCE_METHODS_OPT_",
                "l_OBJC_$_PROTOCOL_INSTANCE_METHODS_",
                "l_OBJC_$_PROP_LIST_",
                "l_OBJC_PROTOCOL_$_",
                "l_OBJC_PROTOCOL_REFERENCE_$_",
                "l_OBJC_CLASS_RO_$_",
                "l_OBJC_METACLASS_RO_$_",
                "l_OBJC_CLASS_PROTOCOLS_$_",
                "l_OBJC_LABEL_PROTOCOL_$_",
                "l_OBJC_$_CATEGORY_CLASS_METHODS_",
                "l_OBJC_$_CATEGORY_INSTANCE_METHODS_",
                "l_OBJC_$_CATEGORY_",
                ""]

    keyword = ""

    keywords.each {|word|

        if symbol.start_with?(word)
            symbol = symbol.gsub(word, "").strip
            keyword = word
            break
        end
    }


    # puts symbol #if symbol.include?('$')

    return {:symbol => symbol, :keyword => keyword}
end

# 得到符号的类型， :defined :undefined :other
def get_symbol_type(mark, keyword)

    defined_symbols = [{:mark => "S", :keyword => ""},
                       {:mark => "t", :keyword => ""},
                       {:mark => "T", :keyword => ""},
                       {:mark => "S", :keyword => "_OBJC_CLASS_$_"},
                       {:mark => "D", :keyword => "_OBJC_CLASS_$_"},
                       {:mark => "S", :keyword => "_OBJC_METACLASS_$_"},
                       {:mark => "D", :keyword => "_OBJC_METACLASS_$_"},
                       {:mark => "s", :keyword => "l_OBJC_$_CLASS_METHODS_"},
                       {:mark => "s", :keyword => "l_OBJC_$_INSTANCE_METHODS_"},
                       {:mark => "s", :keyword => "l_OBJC_$_INSTANCE_VARIABLES_"},
                       {:mark => "s", :keyword => "l_OBJC_CLASS_RO_$_"},
                       {:mark => "s", :keyword => "l_OBJC_METACLASS_RO_$_"},
                       {:mark => "s", :keyword => "l_OBJC_CLASS_PROTOCOLS_$_"}]

    undefined_symbols = [{:mark => "U", :keyword => ""},
                         {:mark => "U", :keyword => "_OBJC_CLASS_$_"},
                         {:mark => "U", :keyword => "_OBJC_METACLASS_$_"},
                         {:mark => "s", :keyword => "l_OBJC_$_PROTOCOL_REFS_"},
                         {:mark => "s", :keyword => "l_OBJC_$_PROTOCOL_METHOD_TYPES_"},
                         {:mark => "s", :keyword => "l_OBJC_$_PROTOCOL_INSTANCE_METHODS_OPT_"},
                         {:mark => "s", :keyword => "l_OBJC_$_PROTOCOL_INSTANCE_METHODS_"},
                         {:mark => "D", :keyword => "l_OBJC_PROTOCOL_$_"},
                         {:mark => "W", :keyword => "l_OBJC_PROTOCOL_$_"},
                         {:mark => "D", :keyword => "l_OBJC_PROTOCOL_$_"},
                         {:mark => "S", :keyword => "l_OBJC_PROTOCOL_REFERENCE_$_"},
                         {:mark => "S", :keyword => "l_OBJC_LABEL_PROTOCOL_$_"},
                         {:mark => "W", :keyword => "l_OBJC_LABEL_PROTOCOL_$_"}]

    # 丢弃的符号，不处理，define和undefined的规则中都存在符号
    other_symbols = [{:mark => "s", :keyword => "l_OBJC_$_PROP_LIST_"},
                     {:mark => "S", :keyword => "_OBJC_IVAR_$_"},
                     {:mark => "D", :keyword => "_OBJC_IVAR_$_"},
                     {:mark => "s", :keyword => "l_OBJC_$_CATEGORY_CLASS_METHODS_"},
                     {:mark => "s", :keyword => "l_OBJC_$_CATEGORY_INSTANCE_METHODS_"},
                     {:mark => "s", :keyword => "l_OBJC_$_CATEGORY_"},
                     {:mark => "d", :keyword => ""},
                     {:mark => "b", :keyword => ""}]

    defined_symbols.each do |pair|
        m_mark = pair[:mark]
        m_keyword = pair[:keyword]
        if mark == m_mark && keyword == m_keyword
            return :defined
        end
    end

    undefined_symbols.each do |pair|
        m_mark = pair[:mark]
        m_keyword = pair[:keyword]
        if mark == m_mark && keyword == m_keyword
            return :undefined
        end
    end

    return :other
end

def parse_tbd_path_name (path_name)

    basename = File.basename(path_name)
    basename = basename.gsub("lib", "").gsub(".a.tbd", "").gsub(".tbd", "")
    basename
end

# 遍历tbd文件，生成一个数组，保存每一个.o文件的符号列表
# 将当前的.o文件的数组列表合并成一个大的符号列表
def parse_lib_symbol(lib_tbd_path_name)

    return if !File.exist?(lib_tbd_path_name)

    all_object = Array.new

    object_content = nil # :name :symbols(:key , :value Hash) :defined_symbols :undefined_symbols :other_symbols

    # 解析出符号并归类
    File.open(lib_tbd_path_name, 'r+').each do |line|

        next if line.strip.length == 0

        # puts line.length.to_s + '   ' + line

        if line.match(/.*\(.*\.o\):.*/) || line.match(/.*:.*.o:/) || object_content == nil

            # 是一个新的o 文件
            # puts "-> " + line
            #
            # if !object_content.empty?
            # end

            object_content = Hash.new
            object_content[:name] = line.split('(')[0]
            object_content[:symbols] = Hash.new
            object_content[:defined_symbols] = Hash.new
            object_content[:undefined_symbols] = Hash.new
            object_content[:other_symbols] = Hash.new
            all_object.push(object_content)
        else

            # puts line
            #
            # mark = nil
            # symbol = nil

            line = line.strip
            # puts "->" + line
            components = line.split(" ")

            if components[0].length == 1
                mark = components[0]
                components.shift
                symbol = components.join(" ")
            else
                mark = components[1]
                components.shift
                components.shift
                symbol = components.join(" ")
            end

            symbol_map = parse_symbol(symbol)

            symbol = symbol_map[:symbol]

            symbol_type = get_symbol_type(mark, symbol_map[:keyword])

            if symbol_type == :defined
                provide_symbols = object_content[:defined_symbols]
                provide_symbols[symbol] = ""
                # puts symbol
            elsif symbol_type == :undefined
                undefined_symbols = object_content[:undefined_symbols]
                undefined_symbols[symbol] = ""
                # puts symbol
            else
                other_symbols = object_content[:other_symbols]
                # puts object_content
                other_symbols[symbol] = ""
            end

            symbols = object_content[:symbols]

            symbol_values = symbols[mark]
            if symbol_values.nil?
                symbol_values = Hash.new
                symbols[mark] = symbol_values
            end

            symbol_values[symbol] = ""

            # puts "    " + mark #+ "->" + symbol

        end
    end

    # 遍历所有的o文件的符号列表，生成整个库的已定义的符号和未知的符号，以及其他可以忽略的符号
    lib_content = Hash.new # :name :defined_symbols :undefined_symbols :other_symbols

    lib_content[:name] = parse_tbd_path_name(lib_tbd_path_name)

    defined_symbols = Hash.new
    undefined_symbols = Hash.new
    other_symbols = Hash.new


    all_object.each do |an_object|
        defined_symbols = defined_symbols.merge(an_object[:defined_symbols])
        undefined_symbols = undefined_symbols.merge(an_object[:undefined_symbols])
        other_symbols = other_symbols.merge(an_object[:other_symbols])
    end


    undefined_symbols.delete_if do |key, value|
        !defined_symbols[key].nil?
    end


    lib_content[:defined_symbols] = defined_symbols
    lib_content[:undefined_symbols] = undefined_symbols
    lib_content[:other_symbols] = other_symbols
    # puts all_object
    # puts lib_content
    # puts lib_content
    lib_content
end


# 解析单个依赖库的符号数据
def parse_lib(lib_path_name)

    return nil if !File.exist?(lib_path_name)

    lib_path_name = File.expand_path(lib_path_name)

    lib_file_name = File.basename(lib_path_name)

    lib_tbd_path_name = File.expand_path("#{$intermediate_dir}")

    lib_tbd_path_name = "#{lib_tbd_path_name}/#{lib_file_name}.tbd"

    create_symbol_file_cmd = "nm #{lib_path_name} > #{lib_tbd_path_name}"

    # puts "#####################################"
    # puts create_symbol_file_cmd

    system create_symbol_file_cmd

    parse_lib_symbol(lib_tbd_path_name)
end


def parse_libs(lib_path_array)

    # 解析所有的库，遍历每一个库的 undefined_symbols 区域，将查找到存在于其他库的 defined_symbols
    all_libs = Hash.new

    # 解析每一个库的符号信息
    lib_path_array.each.map do |path|
        Thread.new do
            puts "begin parse: #{path}\n"
            lib_content = parse_lib(path)
            lib_content[:dependence] = Hash.new if lib_content != nil
            lib_content[:bedependence] = Hash.new if lib_content != nil
            all_libs[lib_content[:name]] = lib_content if lib_content != nil
            puts "#{path} ==> done\n"
        end
    end.map(&:join)


    # 解析每一个库的依赖信息
    all_libs.each_value do |lib_content|

        lib_name = lib_content[:name]
        lib_undefined_symbols = lib_content[:undefined_symbols]
        lib_dependence = lib_content[:dependence]

        lib_undefined_symbols.each_key do |lib_undefined_symbol|

            all_libs.each_value do |compared_content|

                next if lib_content == compared_content

                compared_lib_name = compared_content[:name]

                compared_defined_symbols = compared_content[:defined_symbols]

                if compared_defined_symbols[lib_undefined_symbol] != nil

                    dependence = lib_dependence[compared_lib_name]
                    if dependence == nil
                        dependence = Array.new
                        lib_dependence[compared_lib_name] = dependence
                    end
                    dependence.push(lib_undefined_symbol)

                    lib_undefined_symbols[lib_undefined_symbol] = lib_undefined_symbols[lib_undefined_symbol].to_i + 1
                    compared_defined_symbols[lib_undefined_symbol] = compared_defined_symbols[lib_undefined_symbol].to_i + 1

                    compared_content[:bedependence][lib_name] = ""
                end
            end
        end
    end

    # all_libs.each_value do |lib_content|
    #
    #     undefined_symbols = lib_content[:undefined_symbols]
    #     dependence = lib_content[:dependence]
    #     lib_name = lib_content[:name]
    #
    #     all_libs.each_value do |compared_content|
    #
    #         next if lib_content == compared_content
    #
    #         compared_name = compared_content[:name]
    #
    #         undefined_symbols.each_key do |key|
    #
    #             defined_symbols = compared_content[:defined_symbols]
    #
    #             if defined_symbols[key] != nil
    #                 dependence.push(compared_name)
    #                 compared_content[:bedependence].push(lib_name)
    #                 break
    #             end
    #         end
    #     end
    # end

    # puts all_libs
    # :name :dependence :bedependence
    all_libs
end


########################################################################################################################

def parse_link_cmd(cmd)

    cmd = cmd.gsub("-framework ", "-framework_")

    content = cmd.split(' ')

    libpath = Array.new
    frameworkpath = Array.new
    alllib = Array.new
    allframework = Array.new
    # 解析出各个模块以及地址
    content.each do |line|
        # puts line
        if line.start_with?("-L")
            libpath.push(line.gsub("-L", "").strip)
        elsif line.start_with?("-F")
            frameworkpath.push(line.gsub("-F", "").strip)
        elsif line.start_with?("-l")
            alllib.push(line.gsub("-l", "").strip)
        elsif line.start_with?("-framework_")
            allframework.push(line.gsub("-framework_", "").strip)
        end
    end

    # puts alllib
    # puts allframework

    allpath = Array.new
    # 遍历lib和framework，按照名称，查找对应的目录，如果对应的目录文件存在的话，则将静态库的路径添加到返回的结果中
    alllib.each do |lib|
        name = "lib#{lib}.a"
        libpath.each do |path|
            fullpath = "#{path}/#{name}"
            if File.exist?(fullpath)
                allpath.push(fullpath)
                break
            end
        end
    end

    allframework.each do |framework|

        frameworkpath.each do |path|
            fullpath = "#{path}/#{framework}.framework/#{framework}"
            if File.exist?(fullpath)
                allpath.push(fullpath)
                break
            end
        end
    end

    # 解析出在主工程中的main代码.o中间文件目录，生成.a 之后自动添加到path中
    output_path = cmd.match(/[^\s]*dependency_info.dat/)[0]
    main_path = File.dirname(output_path)
    main_path = parse_main_lib(main_path)
    allpath.push(main_path) if main_path != nil

    allpath
end

def parse_main_lib(path)

    # 遍历path目录下的所有 .o 文件，生成一个大的 .a 文件，
    create_lib_cmd = "cd #{path} && ar cru libMain.a *.o"
    system create_lib_cmd

    "#{path}/libMain.a"
end

########################################################################################################################

$style_label_cache = Hash.new
$color_cache = Hash.new

def gen_style_label_by_name(name, count, path)

    style_label = $style_label_cache[path]

    if style_label == nil
        color = gen_color_by_name(name)
        #  label="2", URL="./symbols.txt"
        style_label = " [color=#{color}, penwidth=5, fontsize=40, label=\"#{count}\", URL=\"#{path}\" ] "
        $style_label_cache[path] = style_label
    end

    style_label
end

def gen_color_by_name(name)

    color = $color_cache[name]

    if color == nil
        r = rand.to_s[0, 4]
        g = rand.to_s[0, 4]
        b = rand.to_s[0, 4]
        color = "\"#{r} #{g} #{b}\""
        $color_cache[name] = color
    end

    color
end

$libs = Hash.new

def get_dependence_count(lib_name, dependence_name)

    lib = $libs[lib_name]
    dependence = lib[:dependence]
    symbols = dependence[dependence_name]
    symbols.length
end

# 生成依赖的箭头图
def gen_graph_dependence_line(lib, lib_name, dependence_name)

    # puts lib[:dependence]
    # puts dependence_name
    count = get_dependence_count(lib_name, dependence_name)
    path = "./symbols/#{lib_name}_#{dependence_name}.txt"

    style_info = gen_style_label_by_name(lib_name, count, path)

    "    \"#{lib_name}\" -> \"#{dependence_name}\" #{style_info};"
end

# 生成关系图
def gen_dependence_graph(lib, graph_content)

    deps = lib[:dependence]
    current_name = lib[:name]

    if deps.length > 0
        deps.each_key do |name|
            line = gen_graph_dependence_line(lib, current_name, name)
            graph_content.push(line)
        end
    else
        line = "    \"#{current_name}\";"
        graph_content.push(line)
    end
end

# 递归添加依赖信息
def recursive_gen_graphviz(libs, current_content, gened_libs, graphviz_content)

    return if current_content.nil?

    current_name = current_content[:name]

    return if gened_libs[current_name] != nil

    gened_libs[current_name] = ""

    deps = current_content[:dependence]

    if deps.length > 0
        deps.each_key do |name|
            line = gen_graph_dependence_line(current_content, current_name, name)
            graphviz_content.push(line)
        end
    else
        line = "    \"#{current_name}\";"
        graphviz_content.push(line)
    end

    deps.each_key do |name|

        lib = libs[name]
        if lib != nil
            lib_deps = lib[:dependence]

            if lib_deps.length > 0
                recursive_gen_graphviz(libs, lib, gened_libs, graphviz_content)
            end
        end
    end
end

# 生成子图依赖
def gen_cluster_graph(libs)

    no_parent_has_child = Array.new
    has_parent_has_child = Array.new
    has_parent_no_child = Array.new
    no_parent_no_child = Array.new

    libs.each_value do |lib|

        # puts lib
        name = lib[:name]
        dependence = lib[:dependence]
        bedependence = lib[:bedependence]

        if dependence.length == 0 && bedependence.length == 0
            no_parent_no_child.push(name)
        elsif dependence.length == 0 && bedependence.length != 0
            has_parent_no_child.push(name)
        elsif dependence.length != 0 && bedependence.length == 0
            no_parent_has_child.push(name)
        elsif dependence.length != 0 && bedependence.length != 0
            has_parent_has_child.push(name)
        end
    end

    {"no_parent_has_child" => no_parent_has_child, "has_parent_has_child" => has_parent_has_child, "has_parent_no_child" => has_parent_no_child, "no_parent_no_child" => no_parent_no_child}
end

def gen_styled_graph_content(main_graph_content)

    styled_content = Hash.new

    main_graph_content.each do |line|
        if line.include?("->")
            line = line.gsub("->", " ")
            comps = line.split(" ")
            styled_content[comps[0].strip] = ""
            styled_content[comps[1].strip] = ""
        else
            comps = line.split(" ")
            styled_content[comps[0].gsub(";", "").strip] = ""
        end
    end

    result = Array.new
    styled_content.each_key do |name|
        name = name.gsub("\"", "")
        # file:///Users/logiph/Experiment/output/index.pdf
        # filepath = File.expand_path("./output/#{name}.pdf")
        color = gen_color_by_name(name)
        line = "    \"#{name}\" [fontsize=60, fontcolor=#{color} , URL=\"./#{name}.pdf\"];"
        result.push(line)
    end
    result
end

def gen_graph_overview_info(main_graph_content)

    styled_content = Hash.new
    relation_count = 0

    main_graph_content.each do |line|
        if line.include?("->")
            line = line.gsub("->", " ")
            comps = line.split(" ")
            styled_content[comps[0].strip] = ""
            styled_content[comps[1].strip] = ""
            relation_count = relation_count + 1
        else
            comps = line.split(" ")
            styled_content[comps[0].gsub(";", "").strip] = ""
        end
    end

    libs_count = styled_content.length

    "基础库数量 #{libs_count}，依赖关系数量 #{relation_count}"
end

def gen_graph_content(main_graph_content, cluster_graph_content)

    full_content = Array.new
    full_content.push("digraph G {")
    full_content.push("    ranksep=2.5;")
    full_content.push("    fontsize=100;")
    full_content.push("    label=\"#{gen_graph_overview_info(main_graph_content)}\";")

    full_content.push(main_graph_content)

    styled_content = gen_styled_graph_content(main_graph_content)
    full_content.push(styled_content)

    # cluster_graph_content.each do |cluster_key, cluster_content|
    #     full_content.push("    subgraph clusterFor#{cluster_key} {")
    #     full_content.push("        label=\"#{cluster_key}\";")
    #
    #     cluster_content.each do |line|
    #         full_content.push("#{line};")
    #     end
    #
    #     full_content.push("}")
    # end

    full_content.push("}")
end

#
def gen_single_graph(content, filename, index)

    puts "graph #{index} ==> #{filename}\n"

    file = File.new("./#{$intermediate_dir}/#{filename}.gv", "w+")
    file.puts(content.uniq)
    file.close

    cmd = "dot -Tpdf ./#{$intermediate_dir}/#{filename}.gv -o ./#{$output_dir}/#{filename}.pdf"
    system cmd

    puts "graph #{index} ==> #{filename} done\n"
end

# 生成单个依赖的架构图
def gen_single_graph_content(libs, name)

    # 生成向下的依赖图
    graph_content = Array.new
    gened_libs = Hash.new
    lib_content = libs[name]
    recursive_gen_graphviz(libs, lib_content, gened_libs, graph_content)

    # 生成被依赖的关系
    bedependence = lib_content[:bedependence]
    bedependence.each_key do |libname|
        line = gen_graph_dependence_line(libs[libname], libname, name)
        graph_content.push(line)
    end

    # puts graph_content.uniq.length.to_s + "--" + graph_content.length.to_s if graph_content.uniq.length != graph_content.length

    # 存在添加多条一样依赖的情况，做下去重
    graph_content.uniq
end

def recursive_traverse_dependences(libs, sublib, sub_dependences, top_lib_name)

    return if sublib == nil

    name = sublib[:name]

    if sub_dependences[name] != nil || name == top_lib_name
        return
    end

    sub_dependences[name] = ""

    dependences = sublib[:dependence]

    dependences.each_key do |name|
        recursive_traverse_dependences(libs, libs[name], sub_dependences, top_lib_name)
    end

end

$count = 0

def shrink_single_lib_dependence(libs, lib)

    # 以当前的name为top顶点，如果解析子依赖又解析到top的话，则不解析了
    shrink_dependences = Array.new
    top_lib_name = lib[:name]
    sub_dependences = Hash.new

    dependence = lib[:dependence] # Hash

    # 先计算出每一个依赖的子树数量，然后生成数组从最高的开始解析
    dependence_rank = Hash.new
    dependence.each_key do |name|
        child_dependences = Hash.new
        recursive_traverse_dependences(libs, libs[name], child_dependences, top_lib_name)
        dependence_rank[name] = child_dependences.length
    end

    puts "-------------------------------"
    puts dependence_rank

    dependence_rank = dependence_rank.sort_by {|name, length| length}
    puts dependence_rank.reverse

    sorted_dependence = Array.new
    dependence_rank.reverse.each do |item|
        sorted_dependence.push(item[0])
    end

    puts sorted_dependence

    # # 大的依赖在前面
    # sorted_dependence = Array.new
    # dependence_rank.each do |name, dependences|
    #
    #     if sorted_dependence.length == 0
    #         sorted_dependence.push(name)
    #     else
    #         last_dependence = sorted_dependence.last
    #         first = sorted_dependence[0]
    #
    #         if dependences.length >= first.length
    #
    #         end
    #
    #     end
    #
    # end

    sorted_dependence.each do |name|
        if sub_dependences[name].nil?
            recursive_traverse_dependences(libs, libs[name], sub_dependences, top_lib_name)
        else
            shrink_dependences.push(name)
        end
    end


    puts "shrink #{top_lib_name} =============================================== "
    puts shrink_dependences
    $count = $count + shrink_dependences.length
    puts "current count #{$count}"

    old_count = dependence.length

    shrink_dependences.each do |name|
        dependence.delete(name)
    end

    new_count = dependence.length

    puts "lib old count: #{old_count} new count: #{new_count}"
end

# 缩减所有依赖库的依赖关系，提升依赖图的生成速度，以及保证依赖图更美观一些
def shrink_libs_dependence(libs)

    # 计算到子树每个节点的路径数，每一个节点路径保留最大的数字，如果遇到小的则替换
    # 根据计算的结果，将lib中的dependence进行缩减，减少不必要的跨层级依赖
    # 深度遍历，然后再广度遍历，将二级已存在的存入剔除的列表中

    libs.each do |name, lib|
        shrink_single_lib_dependence(libs, lib)
    end
end

# 根据mainlib，往下解析各个层级的依赖
def gen_libs_graphviz(libs, mainlibname)

    $libs = libs

    # 深度拷贝
    shrink_libs = Marshal.load(Marshal.dump(libs))
    $exclude_framework.each do |name|
        shrink_libs.delete(name)
    end

    if $enable_shrink_libs
        shrink_libs = shrink_libs_dependence(shrink_libs)
    end

    mainlib_content = shrink_libs[mainlibname]

    # 先依次往下递归添加依赖，递归完成之后，再遍历libs，将没有解析过的依赖添加到图中
    main_graph_content = Array.new
    gened_libs = Hash.new
    recursive_gen_graphviz(shrink_libs, mainlib_content, gened_libs, main_graph_content)

    # 未纳入依赖的，再重新生成一下依赖
    shrink_libs.each do |name, lib|
        if gened_libs[name].nil?
            gen_dependence_graph(lib, main_graph_content)
        end
    end

    # 将依赖分成4种类型的，有父依赖没有子依赖的，有子依赖没有父依赖的，即无子依赖，也无父依赖，父子依赖都有的，cluster
    cluster_graph_content = gen_cluster_graph(shrink_libs)

    # 写入到文件中，调用命令行生成大索引的依赖图
    full_graph_content = gen_graph_content(main_graph_content, cluster_graph_content)
    gen_single_graph(full_graph_content, "Index", "")

    # 解析每一个依赖，调用命令行生成每个依赖的图，多线程的方式生成最终的图
    index = 0
    shrink_libs.each_key.map do |name|
        index = index + 1
        local_index = index
        Thread.new do
            puts "gen graph: #{name}\n"
            lib_content = gen_single_graph_content(shrink_libs, name)
            single_graph_content = gen_graph_content(lib_content, nil)
            gen_single_graph(single_graph_content, name, "#{local_index}/#{shrink_libs.length}")
            puts "#{name} ==> done\n"
        end
    end.map(&:join)

end

########################################################################################################################

# 对象保存到文件
def store_object_to_file(object, filename)

    file = File.new(filename, "w+")
    file.puts(Marshal.dump(object))
    file.close
end

# 从文件中读取对象
def read_object_from_file(filename)
    content = File.open(filename, "r+")
    Marshal.load(content)
end

# 以格式化的形式，将所有的库的依赖关系，保存到文件中，方便定位问题
def store_readable_libs_symbol_to_file(libs)

    # 写入大的依赖关系文件中
    file = File.new("./#{$symbols_dir}/symbols.txt", "w+")

    libs.each do |name, lib|
        dependence = lib[:dependence]
        lib_content = Array.new
        lib_content.push("==> #{name}")
        lib_content.push("        dependence:")
        # 将依赖库，以及依赖库的符号写入文件
        dependence.each do |name, symbols|
            lib_content.push("                #{name}")
            symbols.each do |symbol|
                lib_content.push("                        #{symbol}")
            end
        end

        file.puts(lib_content)
    end

    file.close

    # 将每一个库对另一个库的依赖关系符号也单独保存起来
    # path = "./symbols/#{lib_name}_#{dependence_name}.txt"
    libs.each do |lib_name, lib|
        dependence = lib[:dependence]
        dependence.each do |dependence_name, symbols|

            file = File.new("./#{$output_symbols_dir}/#{lib_name}_#{dependence_name}.txt", "w+")
            content = Array.new

            content.push("lib: #{lib_name}")
            content.push("dependence_lib: #{dependence_name}")
            content.push("dependence_symbol_count: #{symbols.length}")
            content.push("symbols:")

            symbols.each do |symbol|
                content.push("    #{symbol}")
            end

            content.push("\n\n\n\n\n\n\n\n")

            # 重新将所有依赖的内容纳入底部
            dependence.each do |inner_dependence_name, inner_symbols|
                content.push("#{inner_dependence_name}:")
                inner_symbols.each do |inner_symbol|
                    content.push("    #{inner_symbol}")
                end
            end


            file.puts(content)
            file.close
        end
    end
end

########################################################################################################################

def init_path(link_cmd)

    if link_cmd != nil
        comps = link_cmd.split("/")
        path_name = comps.last
        $output_dir = "#{path_name}/#{$output_dir}"
        $intermediate_dir = "#{path_name}/#{$intermediate_dir}"
        $symbols_dir = "#{path_name}/#{$symbols_dir}"
        $output_symbols_dir = "#{path_name}/#{$output_symbols_dir}"
    end

    cmd = "mkdir -p \"#{$output_dir}\" \"#{$intermediate_dir}\" \"#{$symbols_dir}\" \"#{$output_symbols_dir}\" "

    system cmd
end


def main

    begin_time = Time.new

    # 解析配置文件
    load "./igraph.cfg"

    init_path($link_cmd)

    all_libs_path = parse_link_cmd($link_cmd)

    libs_symbols = parse_libs(all_libs_path)

    store_object_to_file(libs_symbols, "./#{$symbols_dir}/libs_symbols.dump")

    # libs_symbols = read_object_from_file("./#{$symbols_dir}/libs_symbols.dump")

    store_readable_libs_symbol_to_file(libs_symbols)

    gen_libs_graphviz(libs_symbols, "Main")

    puts "total time: #{Time.new - begin_time}s"
end

def test


end

main

#
# 目录：output 存放生成的pdf
#      intermediate，gv，tbd，中间的结果文件
#      symbols 大的依赖解析存储文件
#  :name :symbols(:key , :value Hash) :defined_symbols Hash  :undefined_symbols Hash  :other_symbols Hash  :dependence  :bedependence

