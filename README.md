# Behaviour
Tools for easy extraction of basic behavioural readouts

## Prepare_Tracking
An interface-based contour tracking tool.  
*Uses common image processing methods to retrieve mouse contour, center of
gravity, as well as a motion measure (frame-to-frame change in surface).
Works for RGB and thermal movies.*  
![image](https://github.com/user-attachments/assets/c175bb36-4251-4e63-b466-bcca9b22428f)
![image](https://github.com/user-attachments/assets/d465ea2c-ccc3-4ea2-a152-5a90626488ea)


## Check_Freezing
An interface-based "freezing"detection tool.  
*Uses the motion measure output from Prepare_Tracking to extract immobility bout via thresholding.
The user can select a fitting threshold, choose a merging window (if two episodes are closer than x, they are merged), and a minimum duration value (episodes below the value are discarded).
Additionally, each episode can be edited by clicking on it and dragging the start/end time, and "exclusion" periods can be added.*  
![image](https://github.com/user-attachments/assets/6a377057-a12c-4c35-915b-48268d834d98)

## Behaviour_Scorer
An interface-based tool for semi-manual behaviour detection.  
*Uses body part coordinates extracted via Deeplabcut to process custom compound metrics that are then thresholded to extract behaviours. A simple algorithm ensures that behaviours are detected in a logical order and do not overlap.
The compound scores as well as rasters from the different behaviours and the original movie are all integrated within the GUI.
The user can edit some of the threshold directly via the GUI as well as edit the episodes as needed.*  
![image](https://github.com/user-attachments/assets/3b509ac9-9040-4bc8-8611-0cb079c40853)

