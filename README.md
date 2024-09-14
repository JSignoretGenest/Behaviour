# Behaviour
Tools for easy extraction of basic behavioural readouts

## Prepare_Tracking
An interface-based contour tracking tool.  
*Uses common image processing methods to retrieve mouse contour, center of
gravity, as well as a motion measure (frame-to-frame change in surface).
Works for RGB and thermal movies.*  
*Movies can be processed in batches, making the process time-efficient as recordings from a same paradigm/cohort will share similar characteristics.*  
![image](https://github.com/user-attachments/assets/c175bb36-4251-4e63-b466-bcca9b22428f)
![image](https://github.com/user-attachments/assets/d465ea2c-ccc3-4ea2-a152-5a90626488ea)


## Check_Freezing
An interface-based "freezing"detection tool.  
*Uses the motion measure output from Prepare_Tracking to extract immobility bouts via thresholding.
The user can select a fitting threshold, choose a merging window (if two episodes are closer than x, they are merged), and a minimum duration value (episodes below the value are discarded).
Additionally, each episode can be edited by clicking on it and dragging the start/end time, and "exclusion" periods can be added.*  
![image](https://github.com/user-attachments/assets/6a377057-a12c-4c35-915b-48268d834d98)

## Behaviour_Scorer
An interface-based tool for semi-manual behaviour detection.  
*Uses body part coordinates extracted via Deeplabcut to process custom compound metrics that are then thresholded to extract behaviours. A simple algorithm ensures that behaviours are detected in a logical order and do not overlap.
The compound scores as well as rasters from the different behaviours and the original movie are all integrated within the GUI.
The user can edit some of the threshold directly via the GUI as well as edit the episodes as needed.*  
![image](https://github.com/user-attachments/assets/af4dd936-e5dd-4dc8-81b6-d8d407dbe50c)

## Deeplabcut model
Resnet-152 model refined on 4000+ frames from very diverse environments and top cameras, with/without ECG/miniscope/optogenetics connectors and cables.
Body parts: ears, snout, tailbase, tailend, tailmiddle, tailquarter, paws.
Labeling was mainly restricted to non-obstructed areas: the paws will for instance not be detected if they are not visible, which we made use of for behaviour detection.
*Labeled data is available upon request to anyone wishing to use them as training data.*
