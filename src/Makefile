##
## Compiler definitions
##----------------------

CC=gcc
CFLAGS=-O3 -g -mfma -mavx2
CPPFLAGS=

HDF5_LIBS=-L${HDF5_DIR}/lib -lhdf5 -lhdf5_hl
LIBCONFIG_LIB=-L${MAALI_LIBCONFIG_HOME}/lib -lconfig
CFITSIO_LIB=-L${CFITSIO_ROOT}/lib -lcfitsio
CUDA_LIB=-L${NVIDIA_CUDA_HOME}/lib64 -lcudart
LIBS=$(LIBCONFIG_LIB) $(CFITSIO_LIB) $(CUDA_LIB) -lm $(HDF5_LIBS)

##
## List GPU / CUDA architectures we want supported
##-------------------------------------------------

# Kepler support
GPU_ARCH_FLAG=-arch=sm_30

# Pascal support
#GPU_ARCH_FLAG="-gencode arch=compute_60,code=sm_60"

##
## Add gnuplot support (if available)
##-----------------------------------

#CPPFLAGS+="-DGNUPLOT_ENABLE"

##
## Compilation rules
##-------------------

OBJ=devices.o fileaccess.o inputparser.o rmsf.o rmsynthesis.o

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS) $(HDF5_LIBS)

%.o: %.cu
	nvcc -c -o $@ $< -O3 -I${NVIDIA_CUDA_HOME}/include $(HDF5_LIBS) $(GPU_ARCH_FLAG)

rmsythesis: $(OBJ)
	nvcc -o $@ $^ -O3 -I${NVIDIA_CUDA_HOME}/include $(LIBS) $(GPU_ARCH_FLAG)

clean:
	rm *.o rmsythesis
