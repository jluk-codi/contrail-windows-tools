import qbs
import qbs.Environment

CppApplication {
    property string BOOST_ROOT: Environment.getEnv("BOOST_ROOT")

    consoleApplication: true
    files: [
        "main.cpp",
        "pipemitmtool.cpp",
        "pipemitmtool.h",
        "../Common/utils.h",
        "../Common/utils.cpp",
    ]

    cpp.includePaths: [BOOST_ROOT, "../Common/"]
    cpp.libraryPaths: [BOOST_ROOT + "/stage/lib/"]
    cpp.runtimeLibrary: "static"
    cpp.cxxLanguageVersion: "c++11"

    Group {
        fileTagsFilter: product.type
        qbs.install: true
    }
}
