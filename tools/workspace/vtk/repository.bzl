# -*- mode: python -*-
# vi: set ft=python :

"""
Makes selected VTK headers and precompiled shared libraries available to be
used as a C++ dependency. On Ubuntu, a VTK archive, built by the project
maintainers from the Dockerfile and shell scripts in this directory, is
downloaded and unpacked. On macOS, VTK must be installed from the
robotlocomotion/director tap
(https://github.com/RobotLocomotion/homebrew-director) using Homebrew.

Archive naming convention:
    vtk-<version>-<build_number>-<platform>-<arch>.tar.gz

See also: image/package.sh.

Example:
    WORKSPACE:
        load("@drake//tools/workspace:mirrors.bzl", "DEFAULT_MIRRORS")
        load("@drake//tools/workspace/vtk:repository.bzl", "vtk_repository")
        vtk_repository(name = "foo", mirrors = DEFAULT_MIRRORS)

    BUILD:
        cc_library(
            name = "foobar",
            deps = ["@foo//:vtkCommonCore"],
            srcs = ["bar.cc"],
        )

Argument:
    name: A unique name for this rule.
"""

load("@drake//tools/workspace:os.bzl", "determine_os")

VTK_MAJOR_MINOR_VERSION = "9.1"

VTK_MAJOR_MINOR_PATCH_VERSION = "{}.0".format(VTK_MAJOR_MINOR_VERSION)

def _vtk_cc_library(
        os_result,
        name,
        hdrs = None,
        visibility = None,
        deps = None,
        header_only = False,
        linkopts = []):
    hdr_paths = []

    if hdrs:
        includes = ["include/vtk-{}".format(VTK_MAJOR_MINOR_VERSION)]

        if not visibility:
            visibility = ["//visibility:public"]

        for hdr in hdrs:
            hdr_paths.append("{}/{}".format(includes[0], hdr))
    else:
        includes = []

        if not visibility:
            visibility = ["//visibility:private"]

    visibility = ["//visibility:public"]

    if not deps:
        deps = []

    srcs = []

    if os_result.is_macos:
        if not header_only:
            lib_dir = "{}/opt/vtk@{}/lib".format(
                os_result.homebrew_prefix,
                VTK_MAJOR_MINOR_PATCH_VERSION,
            )
            linkopts = linkopts + [
                "-L{}".format(lib_dir),
                "-l{}-{}".format(name, VTK_MAJOR_MINOR_VERSION),
                "-Wl,-rpath,{}".format(lib_dir),
            ]
    elif os_result.is_ubuntu:
        if not header_only:
            # srcs = ["lib/lib{}-{}.so.1".format(name, VTK_MAJOR_MINOR_VERSION)]
            lib_dir = "/home/local/KHQ/ryan.krattiger/Projects/drake/vtk/src/dev/build/install/lib"
            linkopts = linkopts+ [
                    "-L{}".format(lib_dir),
                    "-l{}-{}".format(name, VTK_MAJOR_MINOR_VERSION)
                    ]
    elif os_result.is_manylinux:
        if not header_only:
            # TODO(jwnimmer-tri) Ideally, we wouldn't be hard-coding paths when
            # using manylinux.
            lib_dir = "/opt/vtk/lib"
            linkopts = linkopts + [
                "-L{}".format(lib_dir),
                "-l{}-{}".format(name, VTK_MAJOR_MINOR_VERSION),
            ]
    else:
        fail("Unknown os_result {}".format(os_result))

    content = """
cc_library(
    name = "{}",
    srcs = {},
    hdrs = {},
    includes = {},
    linkopts = {},
    visibility = {},
    deps = {},
)
    """.format(name, srcs, hdr_paths, includes, linkopts, visibility, deps)

    return content

def _impl(repository_ctx):
    os_result = determine_os(repository_ctx)
    if os_result.error != None:
        fail(os_result.error)

    if os_result.is_macos:
        repository_ctx.symlink("{}/opt/vtk@{}/include".format(
            os_result.homebrew_prefix,
            VTK_MAJOR_MINOR_PATCH_VERSION,
        ), "include")
    elif os_result.is_ubuntu:
        inc_dir = "/home/local/KHQ/ryan.krattiger/Projects/drake/vtk/src/dev/build/install/include"
        repository_ctx.symlink(inc_dir, "include")
        # if os_result.ubuntu_release == "18.04":
        #     archive = "vtk-9.1.0-1-bionic-x86_64.tar.gz"
        #     sha256 = "1b51691d09c9fa77a74ad237fe320fed606e071f732f10645efeffa859352bb6"  # noqa
        # elif os_result.ubuntu_release == "20.04":
        #     archive = "vtk-9.1.0-1-focal-x86_64.tar.gz"
        #     sha256 = "b21e8b98ad71da205305bc074d8e3d4208e9dff307ae716384cefb4d1e606d2f"  # noqa
        # else:
        #     fail("Operating system is NOT supported {}".format(os_result))

        # urls = [
        #     x.format(archive = archive)
        #     for x in repository_ctx.attr.mirrors.get("vtk")
        # ]
        # root_path = repository_ctx.path("")

        # repository_ctx.download_and_extract(
        #     urls,
        #     output = root_path,
        #     sha256 = sha256,
        #     type = "tar.gz",
        # )
    elif os_result.is_manylinux:
        repository_ctx.symlink("/opt/vtk/include", "include")
    else:
        fail("Operating system is NOT supported {}".format(os_result))

    file_content = """# -*- python -*-

# DO NOT EDIT: generated by vtk_repository()

licenses([
    "notice",  # Apache-2.0 AND BSD-3-Clause AND MIT
    "reciprocal",  # GL2PS
    "unencumbered",  # Public-Domain
])
"""

    ###########################################################################
    # VTK "Private" Libraries (See: tools/workspace/vtk/README.md)
    file_content += _vtk_cc_library(os_result, "vtkfmt")

    # NOTE: see /tools/wheel/image/vtk-args, this is to avoid packaging glew.
    if os_result.is_manylinux:
        file_content += _vtk_cc_library(os_result, "vtkglew")

    file_content += _vtk_cc_library(os_result, "vtkkissfft")

    file_content += _vtk_cc_library(
        os_result,
        "vtkkwiml",
        hdrs = [
            "vtk_kwiml.h",
            "vtkkwiml/abi.h",
            "vtkkwiml/int.h",
        ],
        visibility = ["//visibility:private"],
        header_only = True,
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtklibharu",
        deps = [
            "@libpng",
            "@zlib",
        ],
    )

    if os_result.is_manylinux:
        file_content += _vtk_cc_library(
            os_result,
            "vtkloguru",
            linkopts = ["-ldl", "-pthread"],
        )
    else:
        file_content += _vtk_cc_library(os_result, "vtkloguru")

    file_content += _vtk_cc_library(
        os_result,
        "vtkmetaio",
        deps = ["@zlib"],
    )

    # NOTE: see homebrew-director, pugixml is installed via brew.
    if not os_result.is_macos:
        file_content += _vtk_cc_library(os_result, "vtkpugixml")

    if os_result.is_manylinux:
        file_content += _vtk_cc_library(
            os_result,
            "vtksys",
            linkopts = ["-ldl"],
        )
    else:
        file_content += _vtk_cc_library(os_result, "vtksys")

    ###########################################################################
    # VTK "Public" Libraries (See: tools/workspace/vtk/README.md)

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonColor",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonComputationalGeometry",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonCore",
        hdrs = [
            "vtkABI.h",
            "vtkABINamespace.h",
            "vtkAOSDataArrayTemplate.h",
            "vtkAbstractArray.h",
            "vtkAssume.h",
            "vtkAutoInit.h",
            "vtkBuffer.h",
            "vtkBuild.h",
            "vtkCollection.h",
            "vtkCommand.h",
            "vtkCommonCoreModule.h",
            "vtkCompiler.h",
            "vtkDataArray.h",
            "vtkDataArrayAccessor.h",
            "vtkDataArrayMeta.h",
            "vtkDataArrayRange.h",
            "vtkDataArrayTupleRange_AOS.h",
            "vtkDataArrayTupleRange_Generic.h",
            "vtkDataArrayValueRange_AOS.h",
            "vtkDataArrayValueRange_Generic.h",
            "vtkDebugLeaksManager.h",
            "vtkDebugRangeIterators.h",
            "vtkDeprecation.h",
            "vtkFeatures.h",
            "vtkFloatArray.h",
            "vtkGenericDataArray.h",
            "vtkGenericDataArray.txx",
            "vtkGenericDataArrayLookupHelper.h",
            "vtkIOStream.h",
            "vtkIdList.h",
            "vtkIdTypeArray.h",
            "vtkIndent.h",
            "vtkInformation.h",
            "vtkInformationVector.h",
            "vtkIntArray.h",
            "vtkLegacy.h",
            "vtkLongArray.h",
            "vtkLongLongArray.h",
            "vtkMath.h",
            "vtkMathConfigure.h",
            "vtkMathPrivate.hxx",
            "vtkMatrixUtilities.h",
            "vtkMeta.h",
            "vtkNew.h",
            "vtkOStrStreamWrapper.h",
            "vtkOStreamWrapper.h",
            "vtkObject.h",
            "vtkObjectBase.h",
            "vtkObjectFactory.h",
            "vtkOptions.h",
            "vtkPlatform.h",
            "vtkPoints.h",
            "vtkRenderingHyperTreeGridModule.h",
            "vtkEventData.h",
            "vtkSelection.h",
            "vtkSetGet.h",
            "vtkSmartPointer.h",
            "vtkSmartPointerBase.h",
            "vtkSMP.h",
            "vtkSMPTools.h",
            "vtkSMPThreadLocal.h",
            "SMP/Common/vtkSMPToolsAPI.h",
            "SMP/Common/vtkSMPToolsImpl.h",
            "SMP/Common/vtkSMPToolsInternal.h",
            "SMP/Common/vtkSMPThreadLocalAPI.h",
            "SMP/Common/vtkSMPThreadLocalImplAbstract.h",
            "SMP/Sequential/vtkSMPThreadLocalImpl.h",
            "SMP/Sequential/vtkSMPToolsImpl.txx",
            "SMP/STDThread/vtkSMPToolsImpl.txx",
            "SMP/STDThread/vtkSMPThreadPool.h",
            "SMP/STDThread/vtkSMPThreadLocalBackend.h",
            "SMP/STDThread/vtkSMPThreadLocalImpl.h",
            "vtkStdString.h",
            "vtkSystemIncludes.h",
            "vtkTimeStamp.h",
            "vtkType.h",
            "vtkTypeInt32Array.h",
            "vtkTypeInt64Array.h",
            "vtkTypeList.h",
            "vtkTypeList.txx",
            "vtkTypeListMacros.h",
            "vtkTypeTraits.h",
            "vtkUnsignedCharArray.h",
            "vtkVTK_USE_SCALED_SOA_ARRAYS.h",
            "vtkVariant.h",
            "vtkVariantCast.h",
            "vtkVariantInlineOperators.h",
            "vtkVersion.h",
            "vtkVersionMacros.h",
            "vtkWeakPointer.h",
            "vtkWeakPointerBase.h",
            "vtkWin32Header.h",
            "vtkWindow.h",
            "vtkWrappingHints.h",
        ],
        deps = [
            ":vtkkwiml",
            ":vtkloguru",
            ":vtksys",
        ],
    )

    vtk_common_data_model_deps = [
        ":vtkCommonCore",
        ":vtkCommonMath",
        ":vtkCommonMisc",
        ":vtkCommonSystem",
        ":vtkCommonTransforms",
        ":vtksys",
    ]

    # pugixml is included with the brew install.
    if not os_result.is_macos:
        vtk_common_data_model_deps.append(":vtkpugixml")
    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonDataModel",
        hdrs = [
            "vtkAbstractCellLinks.h",
            "vtkBoundingBox.h",
            "vtkCell.h",
            "vtkCellArray.h",
            "vtkCellData.h",
            "vtkCellLinks.h",
            "vtkCellType.h",
            "vtkCellTypes.h",
            "vtkCommonDataModelModule.h",
            "vtkDataObject.h",
            "vtkDataSet.h",
            "vtkDataSetAttributes.h",
            "vtkDataSetAttributesFieldList.h",
            "vtkEmptyCell.h",
            "vtkFieldData.h",
            "vtkGenericCell.h",
            "vtkImageData.h",
            "vtkPointData.h",
            "vtkPointSet.h",
            "vtkPolyData.h",
            "vtkPolyDataInternals.h",
            "vtkRect.h",
            "vtkStructuredData.h",
            "vtkVector.h",
        ],
        deps = vtk_common_data_model_deps,
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonExecutionModel",
        hdrs = [
            "vtkAlgorithm.h",
            "vtkCommonExecutionModelModule.h",
            "vtkDemandDrivenPipeline.h",
            "vtkExecutive.h",
            "vtkImageAlgorithm.h",
            "vtkPolyDataAlgorithm.h",
            "vtkStreamingDemandDrivenPipeline.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonMisc",
            ":vtkCommonSystem",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonMath",
        hdrs = [
            "vtkCommonMathModule.h",
            "vtkMatrix4x4.h",
            "vtkTuple.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkkissfft",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonMisc",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonMath",
            ":vtksys",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonSystem",
        deps = [
            ":vtkCommonCore",
            ":vtksys",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkCommonTransforms",
        hdrs = [
            "vtkAbstractTransform.h",
            "vtkCommonTransformsModule.h",
            "vtkHomogeneousTransform.h",
            "vtkLinearTransform.h",
            "vtkTransform.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonMath",
            ":vtksys",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkDICOMParser",
        deps = [":vtksys"],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkFiltersCore",
        hdrs = [
            "vtkFiltersCoreModule.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMath",
            ":vtkCommonMisc",
            ":vtkCommonSystem",
            ":vtkCommonTransforms",
            ":vtksys",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkFiltersGeneral",
        hdrs = [
            "vtkFiltersGeneralModule.h",
            "vtkTransformPolyDataFilter.h",
        ],
        deps = [
            ":vtkCommonComputationalGeometry",
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMath",
            ":vtkCommonMisc",
            ":vtkCommonSystem",
            ":vtkCommonTransforms",
            ":vtkFiltersCore",
            ":vtkfmt",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkFiltersGeometry",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkFiltersCore",
            ":vtksys",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkFiltersHybrid",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMath",
            ":vtkCommonMisc",
            ":vtkCommonTransforms",
            ":vtkFiltersGeometry",
            ":vtkFiltersCore",
            ":vtkFiltersGeneral",
            ":vtkImagingCore",
            ":vtkImagingSources",
            ":vtkRenderingCore",
            ":vtksys",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkFiltersSources",
        hdrs = [
            "vtkCapsuleSource.h",
            "vtkCylinderSource.h",
            "vtkFiltersSourcesModule.h",
            "vtkPlaneSource.h",
            "vtkSphereSource.h",
            "vtkTexturedSphereSource.h",
        ],
        deps = [
            ":vtkCommonComputationalGeometry",
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonTransforms",
            ":vtkFiltersCore",
            ":vtkFiltersGeneral",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkImagingCore",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMath",
            ":vtkCommonTransforms",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkImagingSources",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkImagingCore",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkIOCore",
        hdrs = [
            "vtkAbstractPolyDataReader.h",
            "vtkIOCoreModule.h",
            "vtkWriter.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMisc",
            ":vtksys",
            "@double_conversion",
            "@liblz4",
            "@liblzma",
            "@zlib",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkIOExport",
        hdrs = [
            "vtkExporter.h",
            "vtkGLTFExporter.h",
            "vtkIOExportModule.h",
            "vtkOBJExporter.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonMath",
            ":vtkCommonTransforms",
            ":vtkFiltersGeometry",
            ":vtkImagingCore",
            ":vtkIOCore",
            ":vtkIOGeometry",
            ":vtkIOImage",
            ":vtkIOXML",
            ":vtkRenderingContext2D",
            ":vtkRenderingCore",
            ":vtkRenderingFreeType",
            ":vtkRenderingVtkJS",
            ":vtklibharu",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkIOGeometry",
        hdrs = [
            "vtkIOGeometryModule.h",
            "vtkOBJReader.h",
            "vtkOBJWriter.h",
            "vtkSTLReader.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMisc",
            ":vtkCommonSystem",
            ":vtkCommonTransforms",
            ":vtkFiltersGeneral",
            ":vtkFiltersHybrid",
            ":vtkImagingCore",
            ":vtkIOCore",
            ":vtkIOImage",
            ":vtkIOLegacy",
            ":vtkRenderingCore",
            ":vtksys",
            "@zlib",
        ],
    )

    vtk_io_image_deps = [
        ":vtkCommonCore",
        ":vtkCommonDataModel",
        ":vtkCommonExecutionModel",
        ":vtkCommonMath",
        ":vtkCommonMisc",
        ":vtkCommonSystem",
        ":vtkCommonTransforms",
        ":vtkDICOMParser",
        ":vtkImagingCore",
        ":vtkmetaio",
        ":vtksys",
        "@libjpeg",
        "@libpng",
        "@libtiff",
        "@zlib",
    ]

    # pugixml is included with the brew install.
    if not os_result.is_macos:
        vtk_io_image_deps.append(":vtkpugixml")
    file_content += _vtk_cc_library(
        os_result,
        "vtkIOImage",
        hdrs = [
            "vtkBMPReader.h",
            "vtkBMPWriter.h",
            "vtkIOImageModule.h",
            "vtkImageExport.h",
            "vtkImageReader.h",
            "vtkImageReader2.h",
            "vtkImageWriter.h",
            "vtkJPEGReader.h",
            "vtkJPEGWriter.h",
            "vtkPNGReader.h",
            "vtkPNGWriter.h",
            "vtkTIFFReader.h",
            "vtkTIFFWriter.h",
        ],
        deps = vtk_io_image_deps,
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkIOImport",
        hdrs = [
            "vtkGLTFImporter.h",
            "vtkIOImportModule.h",
            "vtkImporter.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMisc",
            ":vtkCommonTransforms",
            ":vtkFiltersCore",
            ":vtkFiltersSources",
            ":vtkImagingCore",
            ":vtkIOGeometry",
            ":vtkIOImage",
            ":vtkRenderingCore",
            ":vtksys",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkIOLegacy",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMisc",
            ":vtkIOCore",
            ":vtksys",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkIOXMLParser",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkIOCore",
            ":vtksys",
            "@expat",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkIOXML",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMisc",
            ":vtkCommonSystem",
            ":vtkIOCore",
            ":vtkIOXMLParser",
            ":vtksys",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkRenderingCore",
        hdrs = [
            "vtkAbstractMapper.h",
            "vtkAbstractMapper3D.h",
            "vtkActor.h",
            "vtkActorCollection.h",
            "vtkCamera.h",
            "vtkLight.h",
            "vtkMapper.h",
            "vtkPolyDataMapper.h",
            "vtkProp.h",
            "vtkProp3D.h",
            "vtkPropCollection.h",
            "vtkProperty.h",
            "vtkRenderWindow.h",
            "vtkRenderer.h",
            "vtkRenderingCoreModule.h",
            "vtkShaderProperty.h",
            "vtkStateStorage.h",
            "vtkTexture.h",
            "vtkViewport.h",
            "vtkVolume.h",
            "vtkVolumeCollection.h",
            "vtkWindowToImageFilter.h",
        ],
        deps = [
            ":vtkCommonColor",
            ":vtkCommonComputationalGeometry",
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMath",
            ":vtkCommonSystem",
            ":vtkCommonTransforms",
            ":vtkFiltersCore",
            ":vtkFiltersGeneral",
            ":vtkFiltersGeometry",
            ":vtkFiltersSources",
            ":vtksys",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkRenderingContext2D",
        hdrs = [
            "vtkRenderingContext2DModule.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMath",
            ":vtkCommonSystem",
            ":vtkCommonTransforms",
            ":vtkFiltersGeneral",
            ":vtkRenderingCore",
            ":vtkRenderingFreeType",
        ],
    )

    file_content += _vtk_cc_library(
        os_result,
        "vtkRenderingFreeType",
        hdrs = [
            "vtkRenderingFreeTypeModule.h",
        ],
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkFiltersGeneral",
            ":vtkRenderingCore",
        ],
    )

    vtk_rendering_ui_hdrs = [
        "vtkGenericRenderWindowInteractor.h",
        "vtkRenderingUIModule.h",
    ]
    if not os_result.is_macos:
        vtk_rendering_ui_hdrs.append("vtkXRenderWindowInteractor.h")
    file_content += _vtk_cc_library(
        os_result,
        "vtkRenderingUI",
        hdrs = vtk_rendering_ui_hdrs,
        deps = [
            ":vtkRenderingCore",
        ],
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkRenderingVtkJS",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkRenderingSceneGraph",
            ":vtkRenderingCore",
            ":vtkRenderingOpenGL2",
        ],
    )

    vtk_rendering_opengl2_hdrs = [
        "vtkOpenGLHelper.h",
        "vtkOpenGLPolyDataMapper.h",
        "vtkOpenGLShaderProperty.h",
        "vtkOpenGLTexture.h",
        "vtkRenderingOpenGL2Module.h",
        "vtkShader.h",
        "vtkShaderProgram.h",
    ]
    if not os_result.is_macos:
        vtk_rendering_opengl2_hdrs.append("vtkXOpenGLRenderWindow.h")

    if os_result.is_manylinux:
        vtk_glew_library = ":vtkglew"
        vtk_opengl_linkopts = ["-lX11", "-lXt", "-lGLX"]
    else:
        vtk_glew_library = "@glew"
        vtk_opengl_linkopts = []

    file_content += _vtk_cc_library(
        os_result,
        "vtkRenderingOpenGL2",
        visibility = ["//visibility:public"],
        hdrs = vtk_rendering_opengl2_hdrs,
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonExecutionModel",
            ":vtkCommonMath",
            ":vtkCommonSystem",
            ":vtkCommonTransforms",
            ":vtkFiltersGeneral",
            ":vtkRenderingCore",
            ":vtkRenderingUI",
            ":vtksys",
            vtk_glew_library,
            "@opengl",
        ],
        linkopts = vtk_opengl_linkopts,
    )

    # Indirect dependency: omit headers.
    file_content += _vtk_cc_library(
        os_result,
        "vtkRenderingSceneGraph",
        deps = [
            ":vtkCommonCore",
            ":vtkCommonDataModel",
            ":vtkCommonMath",
            ":vtkRenderingCore",
        ],
    )

    # Glob all files for the data dependency of //tools:drake_visualizer.
    file_content += """
filegroup(
    name = "vtk",
    srcs = glob(["**/*"], exclude=["BUILD.bazel", "WORKSPACE"]),
    visibility = ["//visibility:public"],
)
"""

    if os_result.is_macos:
        # Use Homebrew VTK.
        files_to_install = []
    else:
        # Install all files.
        files_to_install = [":vtk"]

    file_content += """
load("@drake//tools/install:install.bzl", "install_files")
install_files(
    name = "install",
    dest = ".",
    files = {},
    visibility = ["//visibility:public"],
)
""".format(files_to_install)

    repository_ctx.file(
        "BUILD.bazel",
        content = file_content,
        executable = False,
    )

vtk_repository = repository_rule(
    attrs = {
        "mirrors": attr.string_list_dict(),
    },
    implementation = _impl,
)
