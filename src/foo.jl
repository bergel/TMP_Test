@testitem "Server configuration settings: transient" begin
    using RAICode.Server
    using RAI_PagerCore
    using ArroyoSalsaStorage.Async: is_task_parallelism_enabled
    using Tracing: DynamicThreshold, FixedThreshold, NoThreshold
    using Tracing: disable_span_threshold, is_span_threshold_set,
        enable_span_threshold_percent, enable_span_threshold_sec, tracing_config

    @testset "Transient config [use_transient=$(use_transient)]" for use_transient in [false, true, nothing]
        pager_config = RAI_PagerCore.pager_config_skeleton()
        pager_config["cloud"]["transient"] = use_transient
        server_config = Configuration(listenany=true, pager_config=pager_config)

        Server.with_rel_server(server_config) do server
            pager = RAI_PagerCore.get_pager()
            cloud_config = RAI_PagerCore.cloud_config(pager, nothing)
            on_transient = RAI_PagerCore.CloudStorage.on_transient_storage(cloud_config)
            @test isnothing(use_transient) || on_transient == use_transient
            @test !isnothing(use_transient) || !on_transient
        end
    end

    @testset "Empty transient config" begin
        pager_config = RAI_PagerCore.pager_config_skeleton()
        server_config = Configuration(listenany=true, pager_config=pager_config)

        Server.with_rel_server(server_config) do server
            pager = RAI_PagerCore.get_pager()
            cloud_config = RAI_PagerCore.cloud_config(pager, nothing)
            on_transient = RAI_PagerCore.CloudStorage.on_transient_storage(cloud_config)
            @test !on_transient
        end
    end

    @testset "Transient storage without a server config" begin
        Server.with_rel_server(; listenany=true) do server
            pager = RAI_PagerCore.get_pager()
            cloud_config = RAI_PagerCore.cloud_config(pager, nothing)
            on_transient = RAI_PagerCore.CloudStorage.on_transient_storage(cloud_config)
            @test !on_transient
        end
    end

    @testset "span threshold" begin
        @testset "Configuration" begin
            @testset "Empty" begin
                c = Configuration()
                @test c.span_threshold_sec == 0
                @test c.span_threshold_percent == 0
            end

            @testset "Only sec" begin
                c = Configuration(["--span-threshold-sec", "0.09"])
                @test c.span_threshold_sec == 0.09
                @test c.span_threshold_percent == 0.0
            end

            @testset "Only percent" begin
                c = Configuration(["--span-threshold-percent", "0.09"])
                @test c.span_threshold_sec == 0
                @test c.span_threshold_percent == 0.09
            end

            @testset "Both percent and sec" begin
                c = Configuration(["--span-threshold-percent", "0.09", "--span-threshold-sec", "0.08"])
                @test c.span_threshold_sec == 0.08
                @test c.span_threshold_percent == 0.09
            end
        end

        @testset "Server" begin
            @testset "Empty" begin
                Server.with_rel_server(Configuration(listenany=true)) do server
                    @test !is_span_threshold_set()
                end
            end

            @testset "Without enabling tracing" begin
                c = Configuration(["--span-threshold-sec", "0.09", "--listenany", "true"])
                Server.with_rel_server(c) do server
                    @test server.config.span_threshold_sec == 0.09
                    @test server.config.span_threshold_percent == 0.0
                    @test !is_span_threshold_set() #because tracing is not enabled
                    @test tracing_config.span_threshold isa NoThreshold
                end
            end

            @testset "Only sec" begin
                c = Configuration(["--span-threshold-sec", "0.09", "--tracing", "datadog", "--listenany", "true"])
                Server.with_rel_server(c) do server
                    @test server.config.span_threshold_sec == 0.09
                    @test server.config.span_threshold_percent == 0.0
                    @test is_span_threshold_set()
                    @test tracing_config.span_threshold isa FixedThreshold
                end
            end

            @testset "Only percent" begin
                c = Configuration(["--span-threshold-percent", "0.05", "--tracing", "datadog", "--listenany", "true"])
                Server.with_rel_server(c) do server
                    @test server.config.span_threshold_sec == 0.0
                    @test server.config.span_threshold_percent == 0.05
                    @test is_span_threshold_set()
                    @test tracing_config.span_threshold isa DynamicThreshold
                end
            end

            @testset "Sec and percent" begin
                c = Configuration(["--span-threshold-percent", "0.05",
                                   "--span-threshold-sec", "0.09",
                                   "--tracing", "datadog",
                                   "--listenany", "true",
                    ])
                Server.with_rel_server(c) do server
                    @test server.config.span_threshold_sec == 0.09
                    @test server.config.span_threshold_percent == 0.05
                    @test is_span_threshold_set()
                    @test tracing_config.span_threshold isa DynamicThreshold
                end
            end

            @testset "Percent and sec" begin
                c = Configuration(["--span-threshold-sec", "0.09",
                                   "--span-threshold-percent", "0.05",
                                   "--tracing", "datadog",
                                   "--listenany", "true"
                    ])
                Server.with_rel_server(c) do server
                    @test server.config.span_threshold_sec == 0.09
                    @test server.config.span_threshold_percent == 0.05
                    @test is_span_threshold_set()
                    @test tracing_config.span_threshold isa DynamicThreshold
                end
            end
        end
    end

    @testset "Task parallelism" begin
        @testset "Default" begin
            c = Configuration(["--listenany", "true"])
            Server.with_rel_server(c) do _
                @test is_task_parallelism_enabled()
            end
        end

        @testset "Explicitely enabled" begin
            c = Configuration(["--task-parallelism", "true", "--listenany", "true"])
            Server.with_rel_server(c) do _
                @test is_task_parallelism_enabled()
            end
        end

        @testset "Explicitely disabled" begin
            c = Configuration(["--task-parallelism", "false", "--listenany", "true"])
            Server.with_rel_server(c) do _
                @test !is_task_parallelism_enabled()
            end
       end
    end

    @testset "Worker heartbeat" begin
        @testset "Default" begin
            c = Configuration(["--listenany", "true"])
            Server.with_rel_server(c) do server
                @test server.config.worker_heartbeat == false
            end
        end

        @testset "Explicitely set" begin
            c = Configuration(["--listenany", "true", "--worker-heartbeat", "true", "--worker-heartbeat-period", "60"])
            Server.with_rel_server(c) do server
                @test server.config.worker_heartbeat == true
                @test server.config.worker_heartbeat_period == 60
            end
        end
    end
end

@testitem "Metadata config" begin
    using RAICode.Server
    using RAICode.Database: MetadataConfig, unsafe_metadata_config,
        reconfigure_metadata_settings, build_timestamp_compatibility_enabled,
        spotcheck_probability, should_check_arroyo_invariants,
        node_consolidations_enabled

    using DataStructures

    # Set defaults to something different that what the default metadata config
    # would contain.
    build_timestamp_compatibility_conf = !build_timestamp_compatibility_enabled()
    spotcheck_probability_conf = 0.123454321
    check_arroyo_invariants_conf = !should_check_arroyo_invariants()
    enable_node_consolidations_conf = !node_consolidations_enabled()

    @testset "Absent metadata config" begin
        Server.with_rel_server(; listenany=true) do _
            # Verify that the default settings for metadata are in place.
            @test unsafe_metadata_config() == MetadataConfig()
        end
    end

    @testset "Pass directly: valid" begin
        try
            dict = DefaultDict{String,Any,Nothing}(nothing)
            dict["use_build_timestamp_compatibility"] = build_timestamp_compatibility_conf
            dict["spotcheck_probability"] = spotcheck_probability_conf
            dict["check_arroyo_invariants"] = check_arroyo_invariants_conf
            dict["enable_node_consolidations"] = enable_node_consolidations_conf

            Server.with_rel_server(; metadata_config=dict, listenany=true) do _
                @test build_timestamp_compatibility_enabled() == build_timestamp_compatibility_conf
                @test spotcheck_probability() == Float32(spotcheck_probability_conf)
                @test should_check_arroyo_invariants() == check_arroyo_invariants_conf
                @test node_consolidations_enabled() == enable_node_consolidations_conf
            end

            # Verify that the default settings were restored.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end

    @testset "Pass directly: valid (string inputs)" begin
        try
            dict = DefaultDict{String,Any,Nothing}(nothing)
            dict["use_build_timestamp_compatibility"] = string(build_timestamp_compatibility_conf)
            dict["spotcheck_probability"] = string(spotcheck_probability_conf)
            dict["check_arroyo_invariants"] = string(check_arroyo_invariants_conf)
            dict["enable_node_consolidations"] = string(enable_node_consolidations_conf)

            Server.with_rel_server(; metadata_config=dict, listenany=true) do _
                @test build_timestamp_compatibility_enabled() == build_timestamp_compatibility_conf
                @test spotcheck_probability() == Float32(spotcheck_probability_conf)
                @test should_check_arroyo_invariants() == check_arroyo_invariants_conf
                @test node_consolidations_enabled() == enable_node_consolidations_conf
            end

            # Verify that the default settings were restored.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end

    @testset "Pass directly: invalid" begin
        try
            build_timestamp_compatibility_conf = "false"
            spotcheck_probability_conf = 1.5
            check_arroyo_invariants_conf = 1
            enable_node_consolidations_conf = -1
            dict = DefaultDict{String,Any,Nothing}(nothing)
            dict["use_build_timestamp_compatibility"] = build_timestamp_compatibility_conf
            dict["spotcheck_probability"] = spotcheck_probability_conf
            dict["check_arroyo_invariants"] = check_arroyo_invariants_conf
            dict["enable_node_consolidations"] = enable_node_consolidations_conf

            Server.with_rel_server(; metadata_config=dict, listenany=true) do _
                default_config = MetadataConfig()
                @test build_timestamp_compatibility_enabled() == parse(Bool, build_timestamp_compatibility_conf)
                @test spotcheck_probability() == default_config.spotcheck_probability
                @test should_check_arroyo_invariants() == Bool(check_arroyo_invariants_conf)
                @test node_consolidations_enabled() == default_config.enable_node_consolidations
            end

            # Verify that the default settings are in place.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end

    @testset "Pass directly: applicable build timestamp=$(btstamp)" for btstamp in ["invalid build timestamp", get_rai_build_timestamp()]
        try
            dict = DefaultDict{String,Any,Nothing}(nothing)
            dict["use_build_timestamp_compatibility"] =
                build_timestamp_compatibility_conf
            dict["applicable_build_timestamp"] = btstamp
            dict["spotcheck_probability"] = spotcheck_probability_conf
            dict["check_arroyo_invariants"] = check_arroyo_invariants_conf
            dict["enable_node_consolidations"] = enable_node_consolidations_conf

            Server.with_rel_server(; metadata_config=dict, listenany=true) do _
                if btstamp == get_rai_build_timestamp()
                    @test build_timestamp_compatibility_enabled() ==
                        build_timestamp_compatibility_conf
                else
                    @test build_timestamp_compatibility_enabled() ==
                        MetadataConfig().use_build_timestamp_compatibility
                end
                @test spotcheck_probability() == Float32(spotcheck_probability_conf)
                @test should_check_arroyo_invariants() == check_arroyo_invariants_conf
                @test node_consolidations_enabled() == enable_node_consolidations_conf
            end

            # Verify that the default settings were restored.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end

    @testset "Pass through YAML: valid" begin
        config_file_path = "engine-metadata-config.yaml"
        try
            open(config_file_path, "w") do io
                # We include in the below YAML file more sections than the
                # test exercises because these should always be present.
                write(io, """
                    general:
                        foo: bla
                    parallelism:
                        foo: bla
                    observability:
                        foo: bla
                    metadata:
                        use_build_timestamp_compatibility: $(build_timestamp_compatibility_conf)
                        spotcheck_probability: $(spotcheck_probability_conf)
                        check_arroyo_invariants: $(check_arroyo_invariants_conf)
                        enable_node_consolidations: $(enable_node_consolidations_conf)
                    """)
            end
            server_config = Configuration([
                "--listenany", "true",
                "--config-file", config_file_path,
            ])
            Server.with_rel_server(server_config) do _
                @test build_timestamp_compatibility_enabled() == build_timestamp_compatibility_conf
                @test spotcheck_probability() == Float32(spotcheck_probability_conf)
                @test should_check_arroyo_invariants() == check_arroyo_invariants_conf
                @test node_consolidations_enabled() == enable_node_consolidations_conf
            end

            # Verify that the default settings were restored.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            rm(config_file_path; force=true)

            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end

    @testset "Pass through YAML: valid (string inputs)" begin
        config_file_path = "engine-metadata-config.yaml"
        try
            open(config_file_path, "w") do io
                # We include in the below YAML file more sections than the
                # test exercises because these should always be present.
                write(io, """
                    general:
                        foo: bla
                    parallelism:
                        foo: bla
                    observability:
                        foo: bla
                    metadata:
                        use_build_timestamp_compatibility: "$(build_timestamp_compatibility_conf)"
                        spotcheck_probability: "$(spotcheck_probability_conf)"
                        check_arroyo_invariants: "$(check_arroyo_invariants_conf)"
                        enable_node_consolidations: "$(enable_node_consolidations_conf)"
                    """)
            end
            server_config = Configuration([
                "--listenany", "true",
                "--config-file", config_file_path,
            ])
            Server.with_rel_server(server_config) do _
                @test build_timestamp_compatibility_enabled() == build_timestamp_compatibility_conf
                @test spotcheck_probability() == Float32(spotcheck_probability_conf)
                @test should_check_arroyo_invariants() == check_arroyo_invariants_conf
                @test node_consolidations_enabled() == enable_node_consolidations_conf
            end

            # Verify that the default settings were restored.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            rm(config_file_path; force=true)

            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end

    @testset "Pass through YAML: invalid" begin
        config_file_path = "engine-metadata-config.yaml"
        build_timestamp_compatibility_conf = "false"
        spotcheck_probability_conf = 1.5
        check_arroyo_invariants_conf = 1
        enable_node_consolidations_conf = -1
        try
            open(config_file_path, "w") do io
                # We include in the below YAML file more sections than the
                # test exercises because these should always be present.
                write(io, """
                    general:
                        foo: bla
                    parallelism:
                        foo: bla
                    observability:
                        foo: bla
                    metadata:
                        use_build_timestamp_compatibility: $(build_timestamp_compatibility_conf)
                        spotcheck_probability: $(spotcheck_probability_conf)
                        check_arroyo_invariants: $(check_arroyo_invariants_conf)
                        enable_node_consolidations: $(enable_node_consolidations_conf)
                    """)
            end
            server_config = Configuration([
                "--listenany", "true",
                "--config-file", config_file_path,
            ])
            Server.with_rel_server(server_config) do _
                default_config = MetadataConfig()
                @test build_timestamp_compatibility_enabled() == parse(Bool, build_timestamp_compatibility_conf)
                @test spotcheck_probability() == default_config.spotcheck_probability
                @test should_check_arroyo_invariants() == Bool(check_arroyo_invariants_conf)
                @test node_consolidations_enabled() == default_config.enable_node_consolidations
            end

            # Verify that the default settings are in place.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            rm(config_file_path; force=true)

            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end

    @testset "Pass through YAML: applicable build timestamp=$(btstamp)" for btstamp in ["invalid build timestamp", get_rai_build_timestamp()]
        config_file_path = "engine-metadata-config.yaml"
        try
            open(config_file_path, "w") do io
                # We include in the below YAML file more sections than the
                # test exercises because these should always be present.
                write(io, """
                    general:
                        foo: bla
                    parallelism:
                        foo: bla
                    observability:
                        foo: bla
                    metadata:
                        use_build_timestamp_compatibility: $(build_timestamp_compatibility_conf)
                        spotcheck_probability: $(spotcheck_probability_conf)
                        check_arroyo_invariants: $(check_arroyo_invariants_conf)
                        enable_node_consolidations: $(enable_node_consolidations_conf)
                        applicable_build_timestamp: "$(btstamp)" # This really has to be a string.
                    """)
            end
            server_config = Configuration([
                "--listenany", "true",
                "--config-file", config_file_path,
            ])
            Server.with_rel_server(server_config) do _
                if btstamp == get_rai_build_timestamp()
                    @test build_timestamp_compatibility_enabled() ==
                        build_timestamp_compatibility_conf
                else
                    @test build_timestamp_compatibility_enabled() ==
                        MetadataConfig().use_build_timestamp_compatibility
                end
                @test spotcheck_probability() == Float32(spotcheck_probability_conf)
                @test should_check_arroyo_invariants() == check_arroyo_invariants_conf
                @test node_consolidations_enabled() == enable_node_consolidations_conf
            end

            # Verify that the default settings were restored.
            @test unsafe_metadata_config() == MetadataConfig()
        finally
            rm(config_file_path; force=true)

            # Restore defaults.
            reconfigure_metadata_settings(nothing)
        end
    end
end
@testitem "Server configuration settings: checking argument types" begin
    using RAICode.Server
    using ArgParse
    import YAML

    # All attributes of Configuration will be tried against these values
    candidate_values = Any["this is a string", 3.14, 3, -10, -20, true, false, 0]

    category_general = ["ip", "port", "port-p2p", "concurrency", "concurrency-limit-before-backoff-error", "enable-debug-natives", "account-name", "engine-name", "listenany", "coordinator-address", "coordinator-port", "precompile-file", "warmup-folder", "warmup-limit", "task-parallelism", "worker-heartbeat", "worker-heartbeat-period", "jemalloc-profile-period"]
    category_observability = ["span-threshold-sec", "span-threshold-percent", "tracing-no-send", "events_service_address", "statsd-ip", "statsd-port", "statsd-metric-emit-interval", "log-julia-typeinf-profiling", "log-julia-llvm-opt-profiling", "tracing" ]
    category_parallelism = ["leaf-nodes-lookup", "leaf-nodes-count", ]

    category_general_dict = Dict([(x .=> "general") for x in category_general])
    category_observability_dict = Dict([(x .=> "observability") for x in category_observability])
    category_parallelism_dict = Dict([(x .=> "parallelism") for x in category_parallelism])

    category = Dict()
    category = merge(category_general_dict, category)
    category = merge(category_observability_dict, category)
    category = merge(category_parallelism_dict, category)


    @testset "Checking Configuration from YAML" begin
        # This test checks that providing an expected type does not raise an error while
        # providing a different type raises an error
        field_type_pairs = zip(fieldnames(Configuration), fieldtypes(Configuration))
        option_name = ""
        current_exception = nothing
        current_code = ""
        for (field, type) in field_type_pairs
            for value in candidate_values
                exception_caught = false
                normalized_name = replace(String(field), "_"=>"-")
                field_category = category[normalized_name]
                d = Dict(field_category => Dict(normalized_name => value))
                try
                    mktemp() do path,io
                        # isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)

                        YAML.write(io, d)

                        # tmp_io = IOBuffer()
                        # YAML.write(tmp_io, d)
                        # current_code = String(take!(tmp_io))

                        flush(io)
                        # if field == :tracing_no_send
                        #     isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
                        # end
                        Configuration(["--config-file", "$(path)"])
                        @test value isa type
                        # @info "OK0" value=value field type
                    end
            catch ex
                    current_exception = ex
                    if ex isa ArgParse.ArgParseError && ex.text == "unrecognized option $(option_name)"
                        continue
                    end
                    exception_caught = true
                end
                issue_symbol_string = (typeof(value) == String && :symbol isa type) ||
                                      (typeof(value) == Symbol && "a string" isa type)
                if value isa type || issue_symbol_string
                    # If what we provide is not expected, then we should not get the exception
                    if exception_caught
                        tmp_io = IOBuffer()
                        YAML.write(tmp_io, d)
                        current_code = String(take!(tmp_io))
                        @info "NOTOK1" value field type current_exception current_code
                    end
                    @test !exception_caught
                else
                    if !exception_caught
                        tmp_io = IOBuffer()
                        YAML.write(tmp_io, d)
                        current_code = String(take!(tmp_io))
                        @info "NOTOK2" value field type current_code
                    end
                    # Else, we should get the exception
                    @test exception_caught
                end
            end
        end
    end

    # @testset "Checking Configuration argument types" begin
    #     # This test checks that providing an expected type does not raise an error while
    #     # providing a different type raises an error
    #     field_type_pairs = zip(fieldnames(Configuration), fieldtypes(Configuration))
    #     option_name = ""
    #     for (field, type) in field_type_pairs
    #         for value in candidate_values
    #             exception_caught = false
    #             try
    #                 normalized_name = replace(String(field), "-"=>"_")
    #                 option_name = "--" * normalized_name
    #                 Configuration([option_name, repr(value)])
    #             catch ex
    #                 if ex isa ArgParse.ArgParseError && ex.text == "unrecognized option $(option_name)"
    #                     continue
    #                 end
    #                 exception_caught = true
    #             end
    #             if value isa type
    #                 # If what we provide is not expected, then we should not get the exception
    #                 if !exception_caught
    #                     isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    #                 end
    #                 @test !exception_caught
    #             else
    #                 # Else, we should get the exception
    #                 if !exception_caught
    #                     isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    #                 end
    #                 @test exception_caught
    #             end
    #         end
    #     end
    # end

    @testset "Checking argument types" begin
        error_is_caught = false
        try
            Configuration([
                "--listenany", "12",
                "--config-file", "42",
            ])
        catch
            error_is_caught = true
        end
        @test error_is_caught
    end
end
@testitem "Server configuration settings: derived functions versions" begin
    using RAICode.Metadata
    using RAICode.Server
    using RAICode.MetadataRegistry

    using Salsa

    using DataStructures
    using Suppressor: @capture_err

    MetadataRegistry.with_temporary_metadata_registry() do _registry
        config = DefaultDict{String,Any}(nothing)

        @testset "Valid override" begin
            fid = "fixpoint_value_9620193887668500045"
            version = 1010100101010101010
            config[fid] = string(version)

            srv = RAIServer(deriveds_versions_config=config)
            reg = Metadata.metadata_registry()
            @test Metadata.get_version(reg[fid]) === DerivedVersion(version)
        end

        @testset "Invalid override: version" begin
            fid = "fixpoint_value_9620193887668500045"
            version = "-1"
            config[fid] = version

            reg = Metadata.metadata_registry()
            current_version = reg[fid]

            RAIServer(deriveds_versions_config=config)

            reg = Metadata.metadata_registry()
            @test reg[fid] === current_version
        end

        @testset "Invalid override: unknown fid" begin
            fid1 = "fixpoint_value_9620193887668500045x"
            version1 = "1"
            config[fid1] = version1

            fid2 = "fixpoint_value_9620193887668500045"
            version2 = 1010100101010101011
            config[fid2] = string(version2)

            RAIServer(deriveds_versions_config=config)
            reg = Metadata.metadata_registry()
            @test !haskey(reg, fid1)
            @test Metadata.get_version(reg[fid2]) === DerivedVersion(version2)
        end

        @testset "Warn when all invalid" begin
            invalid_config = DefaultDict{String,Any}(nothing)
            invalid_config["fixpoint_value_9620193887668500045x"] = "1"
            invalid_config["fixpoint_value_9620193887668500045"] = "-1"

            out = @capture_err begin
                d = Metadata.metadata_registry()
                RAIServer(deriveds_versions_config=invalid_config)
                @test d == Metadata.metadata_registry()
            end
            msg = "None of the supplied versions of derived functions were \
            set. Please inspect previous warnings for any issues."
            @test occursin(msg, out)
        end

        @testset "Empty config" begin
            empty_config = DefaultDict{String,Any}(nothing)

            reg = Metadata.metadata_registry()
            RAIServer(deriveds_versions_config=empty_config)
            @test reg == Metadata.metadata_registry()
        end

        @testset "No config" begin
            reg = Metadata.metadata_registry()
            RAIServer(deriveds_versions_config=nothing)
            @test reg == Metadata.metadata_registry()
        end

        @testset "YAML config" begin
            config_file_path = "engine-deriveds-versions.yaml"
            fid1 = "fixpoint_value_9620193887668500045"
            version1 = 5
            fid2 = "edb_relinfo_10813368873008989247"
            version2 = 6

            try
                open(config_file_path, "w") do io
                    # We include in the below YAML file more sections than the
                    # test exercises because these should always be present.
                    write(io, """
                        general:
                            foo: bla
                        parallelism:
                            foo: bla
                        observability:
                            foo: bla
                        deriveds_versions:
                            $(fid1): $(version1)
                            $(fid2): "$(version2)"
                        """)
                end
                server_config = Configuration([
                    "--listenany", "true",
                    "--config-file", "$(config_file_path)",
                ])
                Server.with_rel_server(server_config) do _
                    reg = Metadata.metadata_registry()
                    @test Metadata.get_version(reg[fid1]) === DerivedVersion(version1)
                    @test Metadata.get_version(reg[fid2]) === DerivedVersion(version2)
                end
            finally
                rm(config_file_path; force=true)
            end
        end

        @testset "YAML config: applicable build timestamp: $btstamp" for btstamp in ["invalid build timestamp", get_rai_build_timestamp()]
            config_file_path = "engine-deriveds-versions.yaml"
            fid1 = "fixpoint_value_9620193887668500045"
            version1 = 1010100101010101010
            current_version1 = Metadata.get_version(
                Metadata.metadata_registry()[fid1]
            )
            fid2 = "edb_relinfo_10813368873008989247"
            version2 = 1010100101010101011
            current_version2 = Metadata.get_version(
                Metadata.metadata_registry()[fid2]
            )

            try
                open(config_file_path, "w") do io
                    # We include in the below YAML file more sections than the
                    # test exercises because these should always be present.
                    write(io, """
                        general:
                            foo: bla
                        parallelism:
                            foo: bla
                        observability:
                            foo: bla
                        deriveds_versions:
                            $(fid1): $(version1)
                            $(fid2): "$(version2)"
                            # The below really has to be a string.
                            applicable_build_timestamp: "$(btstamp)"
                        """)
                end
                server_config = Configuration([
                    "--listenany", "true",
                    "--config-file", "$(config_file_path)",
                ])
                Server.with_rel_server(server_config) do _
                    reg = Metadata.metadata_registry()
                    if btstamp == get_rai_build_timestamp()
                        @test Metadata.get_version(reg[fid1]) === DerivedVersion(version1)
                        @test Metadata.get_version(reg[fid2]) === DerivedVersion(version2)
                    else
                        @test Metadata.get_version(reg[fid1]) === current_version1
                        @test Metadata.get_version(reg[fid2]) === current_version2
                    end
                end
            finally
                rm(config_file_path; force=true)
            end
        end
    end
end
