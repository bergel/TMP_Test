#!/bin/bash

# CLONING AND BUILDING StaticLint.jl
git clone https://github.com/bergel/StaticLint.jl.git
cd StaticLint.jl
echo "HERE: $PWD"
julia --proj -e "import Pkg ; Pkg.Registry.update() ; Pkg.instantiate() ; Pkg.build()"
cd ..

# WRITING FILES ON WHICH LINT SHOULD BE RUN
#cat ${ALL_CHANGED_FILES} > files_to_run_lint.txt
echo "FILES TO BE LINTED"
cat files_to_run_lint.txt

# RUNNING THE CHECK
julia --project=StaticLint.jl -e "
  using StaticLint 
  files_to_run_lint = readlines(\"files_to_run_lint.txt\")
  open(\"result.txt\", \"w\") do output_io 
    for file_to_run_lint in files_to_run_lint
      println(\"RUNNING ON: $file_to_run_lint\")
      StaticLint.run_lint(file_to_run_lint; io=output_io, filters=essential_filters, formatter=MarkdownFormat()) 
    end
  end
"
  
echo "HERE ARE THE RESULTS:"
cat result.txt
echo "END OF RESULTS"
