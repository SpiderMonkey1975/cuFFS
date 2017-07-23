/******************************************************************************
devices.cu
Copyright (C) 2016  {fullname}

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

Correspondence concerning RMSynth_GPU should be addressed to: 
sarrvesh.ss@gmail.com

******************************************************************************/
extern "C" {
#include<cuda_runtime.h>
#include<cuda.h>
#include "structures.h"
#include "constants.h"
#include "devices.h"
#include "fileaccess.h"
__global__ void computeQUP(float *d_qImageArray, float *d_uImageArray, int nLOS, 
                           int nChan, float K, float *d_qPhi, float *d_uPhi, 
                           float *d_pPhi, float *d_phiAxis, int nPhi, 
                           float *d_lambdaDiff2);
}

/*************************************************************
*
* Enable host memory mapping 
*
*************************************************************/
extern "C"
void setMemMapFlag() {
    /* Enable host memory mapping */
    cudaSetDeviceFlags(cudaDeviceMapHost);
    checkCudaError();
}

/*************************************************************
*
* Check if CUDA ERROR flag has been set. If raised, print 
*   error message to stdout and exit.
*
*************************************************************/
extern "C"
void checkCudaError() {
    cudaError_t errorID = cudaGetLastError();
    if(errorID != cudaSuccess) {
        printf("\nERROR: %s", cudaGetErrorString(errorID));
        exit(FAILURE);
    }
}

/*************************************************************
*
* Check for valid CUDA supported devices. If detected, 
*  print useful device information
*
*************************************************************/
extern "C"
struct deviceInfoList * getDeviceInformation(int *nDevices) {
    int dev;
    int deviceCount = NO_DEVICE;
    struct cudaDeviceProp deviceProp;
    struct deviceInfoList *gpuList;
    
    /* Check for valid devices */
    cudaDeviceReset();
    cudaGetDeviceCount(&deviceCount);
    checkCudaError();
    if(deviceCount == NO_DEVICE) {
        printf("\nError: Could not detect CUDA supported GPU(s)\n\n");
        exit(FAILURE);
    }
    printf("\nINFO: Detected %d CUDA-supported GPU(s)\n", deviceCount);
    *nDevices = deviceCount;

    /* Store useful information about each GPU in a structure array */
    gpuList = (deviceInfoList *)malloc(deviceCount * 
      sizeof(struct deviceInfoList));
    for(dev=0; dev < deviceCount; dev++) {
        cudaSetDevice(dev);
        cudaGetDeviceProperties(&deviceProp, dev);
        checkCudaError();
        gpuList[dev].deviceID    = dev;
        gpuList[dev].globalMem   = deviceProp.totalGlobalMem;
        gpuList[dev].constantMem = deviceProp.totalConstMem;
        gpuList[dev].sharedMemPerBlock = deviceProp.sharedMemPerBlock;
        gpuList[dev].maxThreadPerMP = deviceProp.maxThreadsPerMultiProcessor;
        gpuList[dev].maxThreadPerBlock = deviceProp.maxThreadsPerBlock;
        gpuList[dev].threadBlockSize[0] = deviceProp.maxThreadsDim[0];
        gpuList[dev].threadBlockSize[1] = deviceProp.maxThreadsDim[1];
        gpuList[dev].threadBlockSize[2] = deviceProp.maxThreadsDim[2];
        gpuList[dev].warpSize           = deviceProp.warpSize;
        gpuList[dev].nSM                = deviceProp.multiProcessorCount;
        /* Print device info */
        printf("\nDevice %d: %s (version: %d.%d)", dev, deviceProp.name, 
                                                        deviceProp.major, 
                                                        deviceProp.minor);
        printf("\n\tGlobal memory: %f MB", gpuList[dev].globalMem/MEGA);
        printf("\n\tShared memory: %f kB", gpuList[dev].sharedMemPerBlock/KILO);
        printf("\n\tMax threads per block: %d", gpuList[dev].maxThreadPerBlock);
        printf("\n\tMax threads per MP: %d", gpuList[dev].maxThreadPerMP);
        printf("\n\tProcessor count: %d", deviceProp.multiProcessorCount);
        printf("\n\tMax thread dim: (%d, %d, %d)", deviceProp.maxThreadsDim[0], 
                                                   deviceProp.maxThreadsDim[1], 
                                                   deviceProp.maxThreadsDim[2]);
    }
    printf("\n");
    return(gpuList);
}

/*************************************************************
*
* Select the best GPU device
*
*************************************************************/
extern "C"
int getBestDevice(struct deviceInfoList *gpuList, int nDevices) {
    int dev=0;
    int i, maxMem;
    if(nDevices == 1) { dev = 0; }
    else {
        maxMem = gpuList[dev].globalMem;
        for(i=1; i<nDevices; i++) {
            if(maxMem < gpuList[i].globalMem) { 
                maxMem = gpuList[i].globalMem;
                dev = i;
            }
            else { continue; }
        }
    }
    return dev;
}

/*************************************************************
*
* Copy GPU device information of selectedDevice from gpuList 
*  to selectedDevice
*
*************************************************************/
extern "C"
struct deviceInfoList copySelectedDeviceInfo(struct deviceInfoList *gpuList, 
                                             int selectedDevice) {
    int i = selectedDevice;
    struct deviceInfoList selectedDeviceInfo;
    selectedDeviceInfo.deviceID           = gpuList[i].deviceID;
    selectedDeviceInfo.globalMem          = gpuList[i].globalMem;
    selectedDeviceInfo.constantMem        = gpuList[i].constantMem;
    selectedDeviceInfo.sharedMemPerBlock  = gpuList[i].sharedMemPerBlock;
    selectedDeviceInfo.maxThreadPerMP     = gpuList[i].maxThreadPerMP;
    selectedDeviceInfo.maxThreadPerBlock  = gpuList[i].maxThreadPerBlock;
    selectedDeviceInfo.threadBlockSize[0] = gpuList[i].threadBlockSize[0];
    selectedDeviceInfo.threadBlockSize[1] = gpuList[i].threadBlockSize[1];
    selectedDeviceInfo.threadBlockSize[2] = gpuList[i].threadBlockSize[2];
    selectedDeviceInfo.warpSize           = gpuList[i].warpSize;
    selectedDeviceInfo.nSM                = gpuList[i].nSM;
    return selectedDeviceInfo;
}

/*************************************************************
*
* GPU accelerated RM Synthesis function
*
*************************************************************/
extern "C"
int doRMSynthesis(struct optionsList *inOptions, struct parList *params,
                  struct deviceInfoList selectedDeviceInfo) {
    int i, j; 
    float *lambdaDiff2, *d_lambdaDiff2;
    float *qImageArray, *uImageArray;
    float *d_qImageArray, *d_uImageArray;
    float *d_qPhi, *d_uPhi, *d_pPhi;
    float *qPhi, *uPhi, *pPhi;
    float *d_phiAxis;
    dim3 calcThreadSize, calcBlockSize;
    long *fPixel;
    int fitsStatus = 0;
    long nInElements, nOutElements;
    
    /* Set some pixel access limits */
    fPixel = (long *)calloc(params->qAxisNum, sizeof(*fPixel));
    
    /* Allocate memory on the host */
    nInElements = params->qAxisLen1 * params->qAxisLen2;
    nOutElements= inOptions->nPhi * params->qAxisLen2;
    lambdaDiff2 = (float *)calloc(params->qAxisLen1, sizeof(*lambdaDiff2));
    qImageArray = (float *)calloc(nInElements, sizeof(*qImageArray));
    uImageArray = (float *)calloc(nInElements, sizeof(*uImageArray));
    qPhi = (float *)calloc(nOutElements, sizeof(*qPhi));
    uPhi = (float *)calloc(nOutElements, sizeof(*uPhi));
    pPhi = (float *)calloc(nOutElements, sizeof(*pPhi));
    if(lambdaDiff2 == NULL || qImageArray == NULL || uImageArray == NULL ||
       qPhi == NULL || uPhi == NULL || pPhi == NULL) {
       printf("ERROR: Unable to allocate memory on host\n");
       exit(FAILURE);    
    }
    
    /* Allocate memory on the device */
    cudaMalloc(&d_lambdaDiff2, sizeof(*lambdaDiff2)*params->qAxisLen1);
    cudaMalloc(&d_phiAxis, sizeof(*(params->phiAxis))*inOptions->nPhi);
    cudaMalloc(&d_qImageArray, nInElements*sizeof(*qImageArray));
    cudaMalloc(&d_uImageArray, nInElements*sizeof(*uImageArray));
    cudaMalloc(&d_qPhi, nOutElements*sizeof(*qPhi));
    cudaMalloc(&d_uPhi, nOutElements*sizeof(*uPhi));
    cudaMalloc(&d_pPhi, nOutElements*sizeof(*pPhi));
    checkCudaError();

    /* Compute \lambda^2 - \lambda^2_0 once. Common for all threads */
    for(i=0;i<params->qAxisLen1;i++)
        lambdaDiff2[i] = 2.0*(params->lambda2[i]-params->lambda20);
    cudaMemcpy(d_lambdaDiff2, lambdaDiff2, 
               sizeof(*lambdaDiff2)*params->qAxisLen1, cudaMemcpyHostToDevice);
    checkCudaError();
    
    /* Allocate and transfer phi axis info. Common for all threads */
    cudaMemcpy(d_phiAxis, params->phiAxis, 
               sizeof(*(params->phiAxis))*inOptions->nPhi, 
               cudaMemcpyHostToDevice);
    checkCudaError();

    /* Determine what the appropriate block and grid sizes are */
    calcThreadSize.x = selectedDeviceInfo.warpSize;
    calcBlockSize.y  = params->qAxisLen2;
    calcBlockSize.x  = inOptions->nPhi/calcThreadSize.x + 1;
    printf("INFO: Launching %dx%d blocks each with %d threads\n", 
            calcBlockSize.x, calcBlockSize.y, calcThreadSize.x);

    /* Process each line of sight individually */
    //cudaEventRecord(totStart);
    fPixel[0] = 1; fPixel[1] = 1;
    for(j=1; j<=params->qAxisLen3; j++) {
       fPixel[2] = j;
       /* Read one frame at a time. In the rotated cube, this is 
          all sightlines in one DEC row */
       //cudaEventRecord(readStart);
       fits_read_pix(params->qFile, TFLOAT, fPixel, nInElements, NULL, 
                     qImageArray, NULL, &fitsStatus);
       fits_read_pix(params->uFile, TFLOAT, fPixel, nInElements, NULL,
                     uImageArray, NULL, &fitsStatus);
       checkFitsError(fitsStatus);
        
       /* Transfer input images to device */
       cudaMemcpy(d_qImageArray, qImageArray, 
                  nInElements*sizeof(*qImageArray),
                  cudaMemcpyHostToDevice);
       cudaMemcpy(d_uImageArray, uImageArray, 
                  nInElements*sizeof(*qImageArray),
                  cudaMemcpyHostToDevice);
 
       /* Launch kernels to compute Q(\phi), U(\phi), and P(\phi) */
       computeQUP<<<calcBlockSize, calcThreadSize>>>(d_qImageArray, d_uImageArray, 
                         params->qAxisLen2, params->qAxisLen1, params->K, d_qPhi,
                         d_uPhi, d_pPhi, d_phiAxis, inOptions->nPhi, d_lambdaDiff2);

       /* Move Q(\phi), U(\phi) and P(\phi) to host */
       cudaMemcpy(d_qPhi, qPhi, nOutElements*sizeof(*qPhi), cudaMemcpyDeviceToHost);
       cudaMemcpy(d_uPhi, uPhi, nOutElements*sizeof(*qPhi), cudaMemcpyDeviceToHost);
       cudaMemcpy(d_pPhi, pPhi, nOutElements*sizeof(*qPhi), cudaMemcpyDeviceToHost);

       /* Write the output cubes to disk */
       fits_write_pix(params->qPhi, TFLOAT, fPixel, nOutElements, 
                      NULL, qPhi, NULL, &fitsStatus);
       fits_write_pix(params->uPhi, TFLOAT, fPixel, nOutElements,
                      NULL, uPhi, NULL, &fitsStatus);
       fits_write_pix(params->pPhi, TFLOAT, fPixel, nOutElements,
                      NULL, pPhi, NULL, &fitsStatus);
       checkFitsError(fitsStatus);
    }
    
    /* Free all the allocated memory */
    free(qImageArray); free(uImageArray);
    cudaFree(d_qImageArray); cudaFree(d_uImageArray);
    free(qPhi); free(uPhi); free(pPhi);
    cudaFreeHost(d_qPhi); cudaFreeHost(d_uPhi); cudaFreeHost(d_pPhi);
    free(lambdaDiff2); cudaFree(d_lambdaDiff2);
    cudaFree(d_phiAxis);
    free(fPixel);
    
    return(SUCCESS);
}

/*************************************************************
*
* Device code to compute Q(\phi)
*
*************************************************************/
extern "C"
__global__ void computeQUP(float *d_qImageArray, float *d_uImageArray, int nLOS, 
                           int nChan, float K, float *d_qPhi, float *d_uPhi, 
                           float *d_pPhi, float *d_phiAxis, int nPhi, 
                           float *d_lambdaDiff2) {
    int i;
    float myphi;
    /* xIndex tells me what my phi is */
    const int xIndex = blockIdx.x*blockDim.x + threadIdx.x;
    /* yIndex tells me which LOS I am */
    const int yIndex = blockIdx.y*nPhi;
    float qPhi, uPhi, pPhi;
    float sinVal, cosVal;

    if(xIndex < nPhi) {
        myphi = d_phiAxis[xIndex];
        /* qPhi and uPhi are accumulators. So initialize to 0 */
        qPhi = 0.0; uPhi = 0.0;
        for(i=0; i<nChan; i++) {
            sinVal = sinf(myphi*d_lambdaDiff2[yIndex+i]);
            cosVal = cosf(myphi*d_lambdaDiff2[yIndex+i]);
            qPhi += d_qImageArray[yIndex+i]*cosVal + 
                    d_uImageArray[yIndex+i]*sinVal;
            uPhi += d_uImageArray[yIndex+i]*cosVal -
                    d_qImageArray[yIndex+i]*sinVal;
        }
        pPhi = sqrt(qPhi*qPhi + uPhi*uPhi);

        d_qPhi[xIndex] = K*qPhi;
        d_uPhi[xIndex] = K*uPhi;
        d_pPhi[xIndex] = K*pPhi;
    }
}

/*************************************************************
*
* Initialize Q(\phi) and U(\phi)
*
*************************************************************/
extern "C"
__global__ void initializeQUP(float *d_qPhi, float *d_uPhi, 
                              float *d_pPhi, int nPhi) {
    int index = blockIdx.x*blockDim.x + threadIdx.x;

    if(index < nPhi) {
        d_qPhi[index] = 0.0;
        d_uPhi[index] = 0.0;
        d_pPhi[index] = 0.0;
    }
}
