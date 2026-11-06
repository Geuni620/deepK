# Image POC model notices

The optional local background restoration model is MI-GAN by Picsart AI Research,
converted to Core ML by the Mwoyeo project. It is independent of deepK's text
translation providers. Source images are processed in memory on the user's Mac.

Pinned conversion source: `midagedev/mwoyeo` commit
`f81478c22b55c33a02dffee3fe2bf3caf1c5cc3c`,
`tools/inpaint/models/MIGAN_512.mlpackage`.

The model and full original notices are downloaded only by
`scripts/setup-image-inpaint-model.sh`, verified against pinned Git blob hashes,
and kept under `.build/image-translation-poc/models/`. Compiled model files and
the two full notices are included in the local POC application when present.
No model binaries are added to the repository. User images and translations are
not covered by the code or model licenses and are not included as test fixtures.

## MI-GAN weights license

MIT License

Copyright (c) 2024 Picsart AI Research (PAIR)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
