import qbs
import qbs.Environment

CppApplication {
    property string BOOST_ROOT: Environment.getEnv("BOOST_ROOT")

    consoleApplication: true
    files: [
        "fakedata.cpp",
        "fakedata.h",
        "main.cpp",
        "pipetesttool.cpp",
        "pipetesttool.h",
        "../Common/utils.cpp",
        "../Common/utils.h",
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
