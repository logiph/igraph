# igraph
ArchitectureGraphTool

## 主要功能
支持生成iOS项目的各个库的依赖关系图
支持库之间依赖的具体符号查看

## 安装&使用
本机安装好dot命令行工具
clone 本工程到本地目录
修改igraph.cfg 配置文件，将需要生成架构图的工程先选择模拟器编译，然后提取link命令到配置文件中
开启终端执行 ruby ./igraph.rb
将工程名XXX/output/Index.pdf 拖入chrome浏览器即可查看
