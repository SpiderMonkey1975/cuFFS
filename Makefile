##
## Compiler definitions
##----------------------

CC=gcc
CFLAGS=-O3 -g -mfma -mavx2
CPPFLAGS=

HDF5_LIBS=-lhdf5 -lhdf5_hl
LIBCONFIG_LIB=-lconfig
CFITSIO_LIB=-lcfitsio
CUDA_LIB=-lcudart
LIBS=$(LIBCONFIG_LIB) $(CFITSIO_LIB) $(CUDA_LIB) -lm $(HDF5_LIBS)

##
## List GPU / CUDA architectures we want supported
##-------------------------------------------------

# Kepler support
GPU_ARCH_FLAG="-gencode arch=compute_30,code=sm_30"

# Pascal support
#GPU_ARCH_FLAG="-gencode arch=compute_60,code=sm_60"

##
## Test if gnuplot is available
##------------------------------

if ! gnuplot_loc="$(type -p gnuplot)" || [ -z "$gnuplot_loc" ]; then
else
    CPPFLAGS+="-DGNUPLOT_ENABLE"
fi


##
## Compilation rules
##-------------------

OBJ=src/devices.o \
	src/fileaccess.o \
	src/inputparser.c \
	src/rmsf.c \
	src/rmsynthesis.o

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS) $(HDF5_LIBS)

%.0: %.cu
	nvcc -c -o $@ $< -O3  $(HDF5_LIBS) $(GPU_ARCH_FLAG)

rmsythesis: $(OBJ)
	nvcc -o $@ $^ -O3 $(LIBS) $(GPU_ARCH_FLAG)
