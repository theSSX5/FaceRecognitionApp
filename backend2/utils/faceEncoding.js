// utils/faceEncoding.js

const fs = require('fs');
const faceapi = require('face-api.js');
const canvas = require('canvas');

// Configure face-api.js to use node canvas
const { Canvas, Image, ImageData } = canvas;
faceapi.env.monkeyPatch({ Canvas, Image, ImageData });

const path = require('path');

// Initialize face-api.js models (Load them once)
const modelPath = path.join(__dirname, '../models'); // Ensure you have the models in this directory

const loadModels = async () => {
  await faceapi.nets.ssdMobilenetv1.loadFromDisk(modelPath);
  await faceapi.nets.faceRecognitionNet.loadFromDisk(modelPath);
  await faceapi.nets.faceLandmark68Net.loadFromDisk(modelPath);
};

let modelsLoaded = false;

const encodeFace = async (imagePath) => {
  try {
    if (!modelsLoaded) {
      await loadModels();
      modelsLoaded = true;
    }

    const img = await canvas.loadImage(imagePath);
    const detections = await faceapi.detectSingleFace(img).withFaceLandmarks().withFaceDescriptor();

    if (!detections) {
      console.error('No face detected in the image.');
      return null;
    }

    // Convert Float32Array to regular array for JSON storage
    const faceDescriptor = Array.from(detections.descriptor);

    return faceDescriptor;
  } catch (error) {
    console.error('Error in encodeFace:', error);
    return null;
  }
};

module.exports = { encodeFace };