#!/bin/bash

# CLONING AND BUILDING StaticLint.jl
#git clone git@github.com:bergel/StaticLint.jl.git
git clone https://github.com/bergel/StaticLint.jl.git
cd StaticLint.jl
echo "HERE: $PWD"
julia --proj -e "import Pkg ; Pkg.Registry.update() ; Pkg.instantiate() ; Pkg.build()"
cd ..

# RUNNING THE CHECK
julia --project=StaticLint.jl -e "using StaticLint ; open(\"result.txt\") do io StaticLint.run_lint(\"src\"; io) end" 
cat result.txt
