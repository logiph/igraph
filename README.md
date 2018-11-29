# igraph
ArchitectureGraphTool

## 主要功能
- 支持生成iOS项目的各个库的依赖关系图
- 支持库之间依赖的具体符号查看

## 主要用途
- 用于大项目的依赖分析，指导开发做好库之间的解耦工作，提升代码的复用性
- 可基于此工具解析的结果，做集成的卡口，存在不合理的依赖时能发出提醒
- 相当于项目地图，给开发人员提供整个工程的全局视角，指导开发和架构进行工程梳理

## 安装&使用
- 本机安装好dot命令行工具(已安装好brew的话，brew install dot,没有的话安装graphviz工具，该工具自带dot)
- clone 本工程到本地目录
- 修改igraph.cfg 配置文件，将需要生成架构图的工程先选择模拟器编译，然后提取link命令到配置文件中(参见下图)
- 开启终端执行 ruby ./igraph.rb
- 将工程名XXX/output/Index.pdf 拖入chrome浏览器即可查看

![Image text](https://github.com/logiph/igraph/blob/master/step3.jpg)

## 剩余问题
- category的引用方式目前暂时无法解析到
