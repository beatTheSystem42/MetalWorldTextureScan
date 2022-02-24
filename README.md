# MetalWorldTextureScan
Scan the environment and create a textured mesh with ARKit


https://user-images.githubusercontent.com/14043689/155584141-7091cf48-962e-4b1f-9e8e-ee68f1462be5.mov

This project demonstrates how to scan the environment and capture a region as a textured mesh using only built in iOS frameworks.

The ARSession passes the ARAnchors to the Renderer where the world mesh is trimmed to what's inside of a bounding box and displayed using Metal. Camera frames can be saved and used to texture the mesh when you are done scanning.

There are also export and load methods included for demonstrating saving a mesh and texture.
