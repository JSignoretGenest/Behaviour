# Behaviour
Tools for easy extraction of basic behavioural readouts

## Prepare_Tracking
An interface-based contour tracking tool. 

Uses common image processing methods to retrieve mouse contour, center of
gravity, as well as a motion measure (global change in pixels) in an
efficient and reliable way for large batches, with standardized outputs.

      - Works on both RGB and greyscale movies (incl. thermal)
      - For RGB movies,individual or averaged channels can be used
      (sometimes useful for e.g. a red reflective context)
      - Can process a background image to remove from each individual
      frame to get a better tracking (automatic or manual selection of
      the frames to use, different methods to process the resulting
      background)
      - Uses the parallel computing toolbox to increase processing speed
      (several movies can be "prepared" and then batch-processed, in
      parallel; the exact number that should be launched together depends 
      on the number of available workers, usually a normal sized batch of
      mice is OK -that is 10-15 files at a time)

      
