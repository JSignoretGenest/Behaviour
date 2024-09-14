classdef Behaviour_Scorer<handle
    % Behaviour_Scorer - Class to detect/score several behaviours.
    % Initial detection is performed using a combination of contour
    % tracking and DeepLabCut tracking. For each behaviour, different
    % criterion are combined, but the first step is the thresholding of a
    % continuous score based on different parameters. 
    % Mouse characteristics (e.g. length), are automatically detected, and
    % are used, together with the context information (calibration), to
    % automatically select a threshold. Given the wide array of conditions,
    % this sometimes is not accurate enough, and it is possible to manually
    % adjust the threshold if needed. Detected events boundaries can also
    % be adjusted manually.
%     1.	Tail Rattling : just the criteria
%     2.	Grooming : just the criteria
%     3.	Rearing : criteria + no grooming
%     4.	Head dips : criteria + no grooming + no rearing
%     5.	SAP: criteria + no grooming + no head dips AND if parameters set to true, no rearing
%     6.	Immobility: criteria + no TR, no grooming, no rearing, no head dips, no SAP
%     7.	AreaBound: criterion + none of the others
%     8.	Remaining: the rest

    
    
    properties(SetAccess = private, GetAccess = public)
        DefaultParameters
        Parameters
        PlotParameters
        
        % Detection to perform & plot - Shouldn't be changed
        %         DetectionToPlot = {'Immobility','LowMotion','HeadScan','Flight',...
        %             'Rearing','StretchAttend','Grooming','TailRattling'};
        DetectionToPlotBase = {'Rearing','StretchAttend','Grooming','TailRattling','Struggle','Freezing','AreaBound','Flight','Remaining'};
        ExcludePlot = {'Remaining'};
        % Measurements to process & plot (measurements required for the
        % detection are always enabled)
        DefaultMeasurementsToPlot = {'Motion','Speed','AreaExplored','Grooming','TailMotion','HindPawLeft','TotalLength'};
        MeasurementsToPlot
        % Available measures:
        %
        % Grooming:     The grooming score along time -always enabled
        %
        % HindPawLeft   Extension of the paw behind the tailbase
        % HindPawRight  
        %
        % Motion:       Motion measure, just type 'Motion'
        %
        % Speeds:       for any body part, just type 'SpeedBodypart' e.g.
        %               SpeedEarleft
        %               for the global mouse speed, 'SpeedCenterG'
        %
        % StepSpeeds:   for any body part, just type 'StepSpeedBodypart' e.g.
        %               StepSpeedEarleft
        %               for the global mouse stepspeed, 'StepSpeedCenterG'
        %
        % TailLength:   Sum of the different tail segments length
        %               Potentially usefull to detect straub tail
        %
        % TailMotion:   Speed ratio for tail parts to detect tailrattling
        %               always enabled
        %
        % ...
        

        
    end
    
    
    properties(SetAccess = private, GetAccess = public, Hidden = true)
        AllDetected
        Basename
        Behaviours
        Bodyparts
        ClosedArmMask
        ClosedArmVertices
        Coordinates
        CurrentAxis
        CurrentEdit
        CurrentlyPlaying
        CurrentPlayingStatus = false;
        CurrentTime
        CurrentTimeLast
        CurrentWindowLine
        Detection
        DetectionToPlot
        Dragging = false;
        Editing = false;
        Enabled
        EnabledBodyparts
        EnabledBodypartsIndex
        ExclusionRanges
        FieldNames
        File
        FontScaling
        Handles
        Key
        MaskLimits
        MaskShape
        Measurements
        MissingWallRearing
        Movie
        Path
        Playing = false;
        PlayingSingle = false;
        PlayRate = 1;
        PreState
        Reader
        Refractory = false;
        ReplotArms = false;
        Reprocessing = false;
        Score
        SelectedDetection
        Sound
        SoundTimes
        StartPath
        Times
        WallMask
        WallVerticesMask
        WallVerticesVertices
        WallVertices
        WindowSelected
        ZoomValue
    end
    
    
    methods
        % Constructor
        function obj = Behaviour_Scorer
        %% Parameters used for detection
        % Can be changed until the best ones are found but then the same 
        % should be used for ALL the different files (or at least for the 
        % same context)
        
        % Speeds: 
        %   "StepSpeed" is the speed as processed by the distance
        %   between the coordinates at time T1 and the coordinates at time
        %   T2 divided by T2-T1
        %   "Speed" is the sum of the distances frame to frame summed over
        %   the T1?T2 range, and divided by T2-T1
        Tp.Speed.StepBase = 0.3; % Range in s over which speeds are processed
        Tp.Smoothing = 150; % Smoothing value for some measurements (used for Grooming)

        % TailRattling: 
        %   1) difference in speed between a tail reference point and another tail point
            Tp.TailRattling.Reference = 'TailBase'; % Point on the tail to use as
                                                 % reference (should be still
                                                 % during tail rattling
            Tp.TailRattling.Motion = 'TailMiddle';  % Point on the tail to use as
                                                 % the "moving" one
        %   2) Threshold for the tail motion used to detect episodes
             Tp.TailRattling.Threshold = 4.5;
             
        %   3) total distance traveled by the moving point should be lower
        %   than a certain value (sometimes it's rotation not tail rattling)
        %   Same for body itself
            Tp.TailRattling.MaxStepSpeedMoving = 1.5;% in cm/s (tail rattling is stationnary on average)
            Tp.TailRattling.MaxStepSpeedBody = 1.5;% in cm/s (tail rattling is stationnary on average)

            %   4) Merging/minimum duration
            Tp.TailRattling.Merging = 0.1; % in s; if two episodes are closer than that, they are merged
            Tp.TailRattling.MinimumDuration = 0.4; % in s; after merging, all episodes whose duration is inferior are deleted
        
        % Grooming: 
        %   1) product of the total body size (mid-ears to center of
        %   gravity to tail base) by the mid-ears/snout distance, with some
        %   correcting factors
            Tp.Grooming.BaseThreshold = 6.5; % Threshold before size normalization
            Tp.Grooming.Threshold = 6.5; % Threshold after size normalization
            %Tp.Grooming.Ext.BaseThreshold = 6.5; % Threshold before size normalization
            %Tp.Grooming.Threshold = 6.5; % Threshold after size normalization
            
        %   2) Speed (distance traveled) should be low
            Tp.Grooming.MaxStepSpeed = 2; % cm/s
        
        %   3) Motion shouldn't be null (but carefull, with some views, it is very low)
            Tp.Grooming.LowMotion = 0.01;
            
        %   4) Merging/minimum duration
            Tp.Grooming.Merging = 0.1; % in s; if two episodes are closer than that, they are merged
            Tp.Grooming.MinimumDuration = 0.5; % in s; after merging, all episodes whose duration is inferior are deleted
       
        % Stretch-attend
        %   1) (normalized) body length should be high
            Tp.StretchAttend.Length = 6;
            % Tp.StretchAttend.OF.Length = 6;
            % Tp.StretchAttend.EPM.Length = 6;
            
        %   2) Body speed should be low
            Tp.StretchAttend.StepSpeed = 6;
            % Tp.StretchAttend.OF.StepSpeed = 6;
            % Tp.StretchAttend.EPM.StepSpeed = 6;
            % Tp.StretchAttend.LDB.StepSpeed = 8;

        %   3) Hindpaws should be visible and/or extending below the tail
            Tp.StretchAttend.BothHindPaws = 0.2; % Distance below the tail in cm for both paw together
            % Tp.StretchAttend.OF.BothHindPaws = 0.2;
            % Tp.StretchAttend.EPM.BothHindPaws = 0.1;
            % Tp.StretchAttend.CD1.BothHindPaws = 0.2;
            % Tp.StretchAttend.CD2.BothHindPaws = 0.2;
             % Tp.StretchAttend.Ext.BothHindPaws = 0.2;
              % Tp.StretchAttend.ExtHC.BothHindPaws = 0.2;
                % Tp.StretchAttend.LDB.BothHindPaws = 0.1;
            Tp.StretchAttend.SingleHindPaw = 0.1; % Distance below the tail in cm in only one paw is visible/reaches the criterion
            
        %   4) Merging/minimum duration
            Tp.StretchAttend.Merging = 0.1; % in s; if two episodes are closer than that, they are merged
            Tp.StretchAttend.MinimumDuration = 0.5; % in s; after merging, all episodes whose duration is inferior are deleted
    
        % Rearing (wall rearing): uses areas around the context surface and
        % the presence of different body parts in some of them
        % The values might work for all the contexts, but since the view is so
        % different between some of them, we might want to attribute
        % specific values for specific contexts (we are using a 2D
        % threshold on the wall basically...)
        % By default, the "normal" values are the ones like:
        %       Rearing.FirstRing
        % To make specific values for a context on top of that, choose the 
        % keyword (e.g. CD1), and attribute values as:
        %       Tp.Rearing.CD1.FirstRing
        % Keep both the "general" values and the specific values
        
        %   1) First ring around the context surface: rearing if forepaw 
        % and/or both ears above
            Tp.Rearing.FirstRing = 0.7; % width in cm
            % Tp.Rearing.OF.FirstRing = 1.2;
            % Tp.Rearing.EPM.FirstRing = 1;
            % Tp.Rearing.CD1.FirstRing = 1.2;
            % Tp.Rearing.Ext.FirstRing = 0.7;
            % Tp.Rearing.PreExp.FirstRing = 0.5;
            % Tp.Rearing.ExtHC.FirstRing = 1;
            % Tp.Rearing.LDB.FirstRing = 0.7;
            
            Tp.WallRearing.FirstRing = 0.2; % width in cm % Only for the middle walls in LDB
            
            
        %   2) Second ring around the context surface: rearing if snout
        %   above
            Tp.Rearing.SecondRing = 0.8; % width in cm
           % Tp.Rearing.OF.SecondRing = 3.5;
            % Tp.Rearing.EPM.SecondRing = 2;
            % Tp.Rearing.CD1.SecondRing = 2.5;
            % Tp.Rearing.Ext.SecondRing = 1;
            % Tp.Rearing.PreExp.SecondRing = 0.7;
            % Tp.Rearing.ExtHC.SecondRing = 2;
            % Tp.Rearing.LDB.SecondRing = 1.5;
            Tp.WallRearing.SecondRing = 0.3; % width in cm % Only for the middle walls in LDB

        %   3) Third ring around the context surface: max limit for the
        %   body parts
            Tp.Rearing.ThirdRing = 8; % width in cm
            Tp.WallRearing.ThirdRing = 1; % width in cm % Only for the middle walls in LDB

        %   4) Merging/minimum duration
            Tp.Rearing.Merging = 0.1; % in s; if two episodes are closer than that, they are merged
            Tp.Rearing.MinimumDuration = 0.5; % in s; after merging, all episodes whose duration is inferior are deleted
    
        %   5) If rearing, not SAP
            Tp.Rearing.RearingOverSAP = true; % SAP detected at the same time of rearing will be discarded
            
        % HeadDips: same idea, for open arms        
        %   1) First ring around the context surface: headdips if both ears
        %   between this limit and the open arm limit
            Tp.HeadDips.ErosionIn = 1.2; % the mask will atually extend a tiny bit ON the open arm for this width (this helps picks some episodes on black backround, because the ears are then detected more permissively in the target area)
            Tp.HeadDips.FirstRing = 1.2; % width in cm
            
            
        %   2) Second ring around the context surface: HeadDips if snout
        %   further
            Tp.HeadDips.SecondRing = 3.5; % width in cm

        %   3) Third ring around the context surface: max limit for the
        %   body parts
            Tp.HeadDips.ThirdRing = 8; % width in cm
            
        %   4) Merging/minimum duration
            Tp.HeadDips.Merging = 0.1; % in s; if two episodes are closer than that, they are merged
            Tp.HeadDips.MinimumDuration = 0.3; % in s; after merging, all episodes whose duration is inferior are deleted
    
            obj.ReplotArms = true; % Set to true to replot the vertices and closed arms for EPM / middle walls for LDB even if it was already done for the file
            
        % LowMotion: just for display, simple threshold. Corresponds to the old 
        % "freezing" measure. Not to be adjusted manually, only for
        % display.
        % The idea is to later substract grooming, etc from those episodes,
        % and refining them into different categories by looking at e.g.
        % head movements
            Tp.LowMotion.Threshold = 1.5;
            
        % LowLocomotion: same idea, but for locomotion
        
        Tp.Motion.AreaBound.OF = 150;
        Tp.Motion.AreaBound.CD = 50;
        Tp.Motion.AreaBound.PreExp = 50;
        Tp.Motion.AreaBound.Ext = 35;
        Tp.Motion.AreaBound.Opto = 35;
        Tp.Motion.AreaBound.EPM = 50;
        Tp.Motion.AreaBound.LDB = 50;
        %         
%         % Sound frequency list for the different detected behaviours: pay
%         % attention to have the same number
%         DetectionSound = [100,400,700,1000,2000];
%         
%         % Sound priority: if there is overlap, it might sound too messy, so
%         % we will play only one behaviour -we need a priority list
%         SoundPriority = {'TailRattling','Rearing','StretchAttend','Grooming'};
%         SoundMode = true; % to enable or disable the sound
%         
%         % Sampling frequency for the sound -determines the range of
%         % frequencies that can be used to signal behaviours
%         SoundFrequency = 5000;
        
        
        % List of "curves" to plot(on the right side) - By default, the
        % curves relevant to the detected stuff will be plotted anyway.
        % List of potential variables to plot:
        % StepSpeedEarLeft
        %
        %
        
        
        % Bodyparts to plot - names of the bodyparts:
        %   - TailBase
        %   - TailQuarterAnt
        %   - TailMiddle
        %   - TailQuarterPost
        %   - TailEnd
        %   - Snout
        %   - EarLeft
        %   - EarRight
        %   - ForePawLeft
        %   - ForePawRight
        %   - HindPawLeft
        %   - HindPawRight
        obj.EnabledBodyparts = {'all'}; % To plot all -otherwise put this in comment and write a list
        % EnabledBodyparts = {'TailBase', 'Snout'};
        
        % Default values for what to plot (how), that can be changed via
        % the checkboxes in the GUI anyway
        obj.Enabled = struct(...
            'Bodyparts',true,...
            'Center',true,...
            'Contour',true,...
            'Limits',true,...
            'Zoom',false,...
            'DetectionVisual',true,...
            'AreaBound',true);
        
        % Pre-time
        obj.PlotParameters.PreTime = 3; % Time in second before an event
                                        % that will be targeted when
                                        % clicking "Next event": allows to
                                        % see the transition, especially
                                        % when playing
        obj.PlotParameters.PostTime = 2;% Time in second after the event 
                                        % after which playing will stop if 
                                        % the playing status was off before
                                        % jumping the range
        
                                        
        % Auto-zoom
        obj.PlotParameters.MouseSpace = 15; % Size of the zooming area around the center of gravity, in cm
        
        % Marker colors for the bodyparts(if enabled)
        obj.PlotParameters.MarkersInnerColor.All = 'k'; % Color inside the marker
        obj.PlotParameters.MarkersOuterColor.All = 'w'; % Color around the marker, to give a good contrast
        % Colors for the global tracking(if enabled)
        obj.PlotParameters.MouseContourColor = 'g'; % Color of the mouse contour
        obj.PlotParameters.MouseCenterGColor = 'g'; % Color of the mouse center of gravity
        
        % Marker types for the bodyparts(if enabled)
        obj.PlotParameters.MarkersShape.All = '+'; % Color inside the marker

        % Marker sizes for the bodyparts(if enabled)
        obj.PlotParameters.MarkersInnerSize.All = 7; % Size of the inner region
        obj.PlotParameters.MarkersOuterSize.All = 9; % Size of the outer region
        
        % To give a specific look to a bodypart use, e.g.:
        obj.PlotParameters.MarkersShape.Snout = 'o'; % Color inside the marker
        obj.PlotParameters.MarkersInnerColor.Snout = 'r'; % Color inside the marker
        obj.PlotParameters.MarkersOuterColor.Snout = 'w'; % Color around the marker, to give a good contrast
        obj.PlotParameters.MarkersInnerSize.Snout = 5; % Size of the inner region
        obj.PlotParameters.MarkersOuterSize.Snout = 7; % Size of the outer region
        DC = DefColors;
        obj.PlotParameters.MarkersShape.HindPawRight = 'o'; % Color inside the marker
        obj.PlotParameters.MarkersInnerColor.HindPawRight = DC(1,:); % Color inside the marker
        obj.PlotParameters.MarkersOuterColor.HindPawRight = 'w'; % Color around the marker, to give a good contrast
        obj.PlotParameters.MarkersInnerSize.HindPawRight = 5; % Size of the inner region
        obj.PlotParameters.MarkersOuterSize.HindPawRight = 7; % Size of the outer region
        obj.PlotParameters.MarkersShape.HindPawLeft = 'o'; % Color inside the marker
        obj.PlotParameters.MarkersInnerColor.HindPawLeft = DC(1,:); % Color inside the marker
        obj.PlotParameters.MarkersOuterColor.HindPawLeft = 'w'; % Color around the marker, to give a good contrast
        obj.PlotParameters.MarkersInnerSize.HindPawLeft = 5; % Size of the inner region
        obj.PlotParameters.MarkersOuterSize.HindPawLeft = 7; % Size of the outer region

        % To choose the colors of their contours:
        DC = DefColors;
        obj.PlotParameters.RearingLimitsColor.ZeroRing = 'c';
        obj.PlotParameters.RearingLimitsColor.FirstRing = 'c';
        obj.PlotParameters.RearingLimitsColor.SecondRing = 'c';
        obj.PlotParameters.HeadDipsLimitsColor.ZeroRing = DC(3,:);
        obj.PlotParameters.HeadDipsLimitsColor.FirstRing = DC(3,:);
        obj.PlotParameters.HeadDipsLimitsColor.SecondRing = DC(3,:);
        
        % To choose the width of the bands showing the events on the movie
        % (% of the X axis)
%         obj.PlotParameters.OverlayBandWidth = 10; % Radius 
        % Considering the increase in detected behaviours, now automated
        obj.PlotParameters.OverlayFaceAplha = 0.25; % Transparency
        
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%%%%%%%%% END OF THE EDITABLE SECTION %%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        
        % Just because we cannot have enough comments with a struct call,
        % and because it's very long to write obj.Parameters. for every
        % line:ll
        obj.FieldNames = {'TailRattling','Grooming','StretchAttend','Rearing','WallRearing','Speed','HeadDips','Smoothing','Motion'};
        for FN = 1 : numel(obj.FieldNames)
            obj.DefaultParameters.(obj.FieldNames{FN}) =  Tp.(obj.FieldNames{FN});
        end
        
        % Figure
        set(0,'Units','pixels')
        Scrsz = get(0,'ScreenSize');
        obj.Handles.MainFigure = figure('Position',[0 40 Scrsz(3) Scrsz(4)-70],...
            'MenuBar','figure','Color',[0.25,0.25,0.25]);
        obj.Handles.MainFigure.WindowState = 'maximized'; % deals with windows taskbar so better than guessing the position
        obj.Handles.MainFigure.WindowKeyPressFcn = @(src,evt)obj.PressKeyCB(src,evt); % Callback to catch key presses to accomplish different actions:
            % SPACE bar will play/pause the movie
            % RETURN when editing a range will exit the editing mode
            % BACKSPACE will revert back the last range editing made
            % DELETE when editing a range will delete it
            % RIGHTARROW will go to the next event
            % LEFTARROW will go to the previous event
            
            % Font scaling for different screen resolutions
        obj.FontScaling = min([Scrsz(3)/1920,Scrsz(4)/1080]);
        
        % Movie display axes
        obj.Handles.Player.Axes = axes('Position',[0.065 0.35 0.45 0.6],'Color','k'); hold on
        hold(obj.Handles.Player.Axes,'on')
        obj.Handles.Player.Axes.XAxis.Visible = 'off';
        obj.Handles.Player.Axes.YAxis.Visible = 'off';
        % We'll need to know the size in px to keep the movie's ratio
        obj.Handles.Player.Axes.Units = 'pixels';
        obj.Handles.Player.AbsolutePosition = obj.Handles.Player.Axes.Position;
        obj.Handles.Player.Axes.Units = 'normalized';
        % Set default limits (just to have something else than [0 1])
        obj.Handles.Player.Axes.XLim = [1 100];
        obj.Handles.Player.Axes.YLim = [1 100];
        
       
        % Player
        obj.Handles.UIElements.PlayButton = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.05+0.45/2-0.075/2 0.3 0.075 0.04],...
            'String','Play',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.Play_CB});
        obj.Handles.UIElements.SlowerButton = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.05+0.45/2-0.075/2-0.03 0.3 0.03 0.04],...
            'String','< <',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.Slower_CB});
        obj.Handles.UIElements.FasterButton = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.05+0.45/2+0.075/2 0.3 0.03 0.04],...
            'String','> >',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.Faster_CB});
        obj.Handles.UIElements.CurrentTimeEdit = uicontrol('Style','edit',...
            'Units','Normalized','Position',[0.05+0.45/2+0.075/2+0.03+0.03/2 0.3 0.075 0.04],...
            'String','0',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.CurrentTime_CB});
        obj.Handles.UIElements.PlayRateLegend = uicontrol('Style','edit',...
            'Units','Normalized','Position',[0.05+0.45/2-0.075/2-0.03-0.03/2-0.04 0.3 0.04 0.04],...
            'String','x1',...
            'FontSize', obj.FontScaling *17,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Enable','inactive');
        
        obj.Handles.UIElements.EnableContour = uicontrol('Style','checkbox',...
            'Units','Normalized','Position',[0.005 0.85 0.06 0.04],...
            'String','Contour',...
            'Value',obj.Enabled.Contour,...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','left',...
            'Callback',{@(~,~)obj.EnableContour_CB});
        
        obj.Handles.UIElements.EnableCenter = uicontrol('Style','checkbox',...
            'Units','Normalized','Position',[0.005 0.8 0.06 0.04],...
            'String','Center',...
            'Value',obj.Enabled.Center,...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','left',...
            'Callback',{@(~,~)obj.EnableCenter_CB});
        
        obj.Handles.UIElements.EnableBodyparts = uicontrol('Style','checkbox',...
            'Units','Normalized','Position',[0.005 0.75 0.06 0.04],...
            'String','Bodyparts',...
            'Value',obj.Enabled.Bodyparts,...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','left',...
            'Callback',{@(~,~)obj.EnableBodyparts_CB});
        
        obj.Handles.UIElements.EnableZoom = uicontrol('Style','checkbox',...
            'Units','Normalized','Position',[0.005 0.7 0.06 0.04],...
            'String','Zoom',...
            'Value',obj.Enabled.Zoom,...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','left',...
            'Callback',{@(~,~)obj.EnableZoom_CB});
        
        obj.Handles.UIElements.EnableLimits = uicontrol('Style','checkbox',...
            'Units','Normalized','Position',[0.005 0.65 0.06 0.04],...
            'String','Limits',...
            'Value',obj.Enabled.Limits,...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','left',...
            'Callback',{@(~,~)obj.EnableLimits_CB});
        
        obj.Handles.UIElements.EnableDetectionVisual = uicontrol('Style','checkbox',...
            'Units','Normalized','Position',[0.005 0.6 0.06 0.04],...
            'String','Visualize',...
            'Value',obj.Enabled.DetectionVisual,...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','left',...
            'Callback',{@(~,~)obj.EnableDetectionVisual_CB});
        
        obj.Handles.UIElements.EnableAreaBound = uicontrol('Style','checkbox',...
            'Units','Normalized','Position',[0.005 0.55 0.06 0.04],...
            'String','Area explored',...
            'Value',obj.Enabled.AreaBound,...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','left',...
            'Callback',{@(~,~)obj.EnableAreaBound_CB});
        
        obj.Handles.LoadSession_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.63 0.95 0.075 0.04],...
            'String','Load session',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.LoadSession('Normal')},...
            'Enable','on');
        
        obj.Handles.AddExclusionRange_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.975-0.125 0.95 0.125 0.04],...
            'String','Add exclusion range',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.AddExclusionRange},...
            'Enable','on');
        
        obj.Handles.SaveSession_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.975-0.075 0.005 0.075 0.04],...
            'String','Save results',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.SaveSession},...
            'Enable','on');
        obj.Handles.ReRunAlgorithm_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.975-0.075-0.125 0.005 0.125 0.04],...
            'String','Rerun algorithm',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.ReRunAlgorithm},...
            'Enable','on');
        
        obj.Handles.StartPath_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.55 0.95 0.075 0.04],...
            'String','Start path',...
            'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.StartPathCB},...
            'Enable','on');
        
        % Hidden buttons for ranges editing
        obj.Handles.InsertRange_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.0800 0.005 0.075 0.04],...
            'String','Insert range',...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.InsertRangeCB},...
            'Enable','off','Visible','off');
        
        obj.Handles.DeleteRange_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.08+0.075 0.005 0.075 0.04],...
            'String','Delete range',...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.DeleteRangeCB},...
            'Enable','off','Visible','off');
        
        obj.Handles.ChangeRange_Button = uicontrol('Style','pushbutton',...
            'Units','Normalized','Position',[0.5-0.1 0.005 0.1 0.04],...
            'String','Change to rearing',...
            'FontSize', obj.FontScaling *12,'FontName','Arial','FontWeight','b',...
            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
            'HorizontalAlignment','center',...
            'Callback',{@(~,~)obj.ChangeRangeCB},...
            'Enable','off','Visible','off');
        end
        
        
        function LoadSession(obj,Mode)
            if ~(strcmpi(Mode,'EPM_Reload')||strcmpi(Mode,'LDB_Reload'))
                % Load file
                if isempty(obj.StartPath),
                    Experimenters = DataBase.Lists.GetList('Experimenters');
                    CurrentExperimenter = Experimenters(strcmpi(Experimenters(:,2),getenv('username')),1);
                    [File, Path] = uigetfile({'*.csv','DLC output file';
                        },'Please choose a file...',['G:\' CurrentExperimenter{1} '\Data\CalciumImaging\']);
                else
                    [File, Path] = uigetfile({'*.csv','DLC output file';
                        },'Please choose a file...',[obj.StartPath]);
                end
                if isempty(File) | File == 0,
                    return
                end
                if contains(File,'_IRtoBW')
                    if contains(File,'LDB')
                        Basename = strsplit(File,'_IRtoBW');
                    else
                        warning(['_IRtoBW files shouldn''t be used for non-LDB recordings. Aborting.']);
                        return
                    end
                else
                    Basename = strsplit(File,'DLC');
                end
                Basename = Basename{1};
                if isfield(obj.Handles,'SessionName'),
                    delete(obj.Handles.SessionName);
                end
                
                % Check that we have all we need
                TrackingFile = [Path  Basename '_Tracking.mat'];
                if exist(TrackingFile,'file') ~=2
                    warning(['No tracking file was found for session ' Basename '. Aborting.']);
                    return
                end
                
                MeasurementsToPlot = obj.DefaultMeasurementsToPlot;
                % Differenciate between LDB and the others
                if contains(Basename,'LDB')
                    Movie = [Path  Basename '_IRtoBW.avi'];
                    if exist(Movie,'file') ~=2
                        warning(['No _IRtoBW movie was found for session ' Basename '. Aborting.']);
                        return
                    end
                    Key = 'Thermal';
                    MeasurementsToPlot = MeasurementsToPlot(~contains(MeasurementsToPlot,'Tail'));
                else
                    Movie = [Path  Basename '.avi'];
                    if exist(Movie,'file') ~=2
                        warning(['No movie was found for session ' Basename '. Aborting.']);
                        return
                    end
                    Key = 'RGB';
                end
                
                Tracking = load(TrackingFile);
                if isfield(Tracking,Key),
                    if isfield(Tracking.(Key).Parameters,'Calibration'),
                        PxCmRatio = Distance2D(Tracking.(Key).Parameters.Calibration.Line(1,:),Tracking.(Key).Parameters.Calibration.Line(2,:))/Tracking.(Key).Parameters.Calibration.Length;
                        disp(['Calibration for session ' Basename ': ' num2str(0.1*round(10*PxCmRatio)) ' px/cm'])
                    else
                        
                        PxCmRatio = 10;
%                         warning(['No context calibration was found for session ' Basename '. Aborting.']);
%                         return
                    end
                    if isfield(Tracking.(Key), 'MotionMeasure'),
                        Motion = Tracking.(Key).MotionMeasure;
                        CenterG = Tracking.(Key).Center;
                        Contour = Tracking.(Key).Contour;
                    else
                        warning(['No motion data was found for session ' Basename '. Aborting.']);
                        return
                    end
                    
                    if isfield(Tracking.(Key),'Times') && ~isempty(Tracking.(Key).Times)
                        Times = Tracking.(Key).Times;
                    elseif isfield(Tracking.(Key),'MovieTimes')
                        Times = Tracking.(Key).MovieTimes;
                        warning(['Using MovieTimes as times because real timestamps could not be found.']);
                    else
                        warning(['No timestamps were found for session ' Basename '. Aborting.']);
                        return
                    end
                    if isfield(Tracking.(Key).Parameters,'Mask')
                        MaskLimits = Tracking.(Key).Parameters.Mask;
                        MaskShape = Tracking.(Key).Parameters.Shape.Type;
                    else
                        warning(['No context limits were found for session ' Basename '. Aborting.']);
                        return
                    end
                    
                    % If we got here -we will process that file: update
                    obj.MeasurementsToPlot = MeasurementsToPlot;
                    obj.Key = Key;
                    obj.Basename = Basename;
                    obj.Path = [Path filesep];
                    obj.File = fullfile(Path,File);
                    obj.Movie = Movie;
                    obj.Parameters.PxCmRatio = PxCmRatio;
                    obj.Coordinates.CenterG = CenterG;
                    obj.Coordinates.Contour = Contour;
                    obj.Times = Times;
                    obj.MaskLimits = MaskLimits;
                    obj.MaskShape = MaskShape;
                    
                    % Reset 
                    obj.Measurements = [];
                    obj.Detection = [];
                    obj.Measurements.Data.Motion = smoothdata(Motion,'gaussian',10);
                    
                    % Remove overlay axes
                    if isfield(obj.Handles,'OverlayAxes')
                        delete(obj.Handles.OverlayAxes)
                    end
                    
                    % Restore default parameters
                    for FN = 1 : numel(obj.FieldNames)
                        obj.Parameters.(obj.FieldNames{FN}) =  obj.DefaultParameters.(obj.FieldNames{FN});
                    end
                    
                    % Check whether we have already processed that session
                    BehaviourFile = [Path  Basename '_Behaviour.mat'];
                    obj.Reprocessing = false;
                    obj.DetectionToPlot = obj.DetectionToPlotBase;
                    if ~strcmpi(obj.Key,'RGB')
                        obj.DetectionToPlot = obj.DetectionToPlot(~contains(obj.DetectionToPlot,'Tail'));
                    end
                    
                    if exist(BehaviourFile,'file') == 2
                        Answer = questdlg(['The session' Basename ' was already processed.' newline ...
                            'What do you want to do?'],'Please choose...',...
                            'Reprocess again.',...
                            'Load the previous processing.',...
                            'Load the previous processing.');
                        if strcmpi(Answer, 'Load the previous processing.')
                            Loaded = load(BehaviourFile);
                            
                            obj.Parameters = Loaded.Parameters;
                            if ~any(contains(obj.Parameters.DetectionToPlot,'WallRearing'))
                               obj.MissingWallRearing = true; 
                            end
                            if contains(Basename, 'LDB') && ~isfield(obj.Parameters,'WallRearing') %Legacy
                                obj.Parameters.WallRearing = obj.DefaultParameters.WallRearing;
                            end
                            for DTP = 1 : numel(obj.Parameters.DetectionToPlot)
                                if ~contains(obj.DetectionToPlot,obj.Parameters.DetectionToPlot(DTP))
                                    obj.DetectionToPlot = [obj.DetectionToPlot obj.Parameters.DetectionToPlot(DTP)];
                                end
                            end
                            for MTP = 1 : numel(obj.Parameters.MeasurementsToPlot)
                                if ~contains(obj.MeasurementsToPlot,obj.Parameters.MeasurementsToPlot(MTP))
                                    obj.MeasurementsToPlot = [obj.MeasurementsToPlot obj.Parameters.MeasurementsToPlot(MTP)];
                                end
                            end
                            if ~isempty(obj.Detection) && isfield(obj.Detection,'Data')
                                obj.Detection = rmfield(obj.Detection,'Data');
                            end
                            if ~isempty(obj.Detection) && isfield(obj.Detection,'Logical')
                                obj.Detection = rmfield(obj.Detection,'Logical');
                            end
                            for DTP = 1 : numel(obj.DetectionToPlot)
                                if isfield(Loaded,obj.DetectionToPlot{DTP})
                                    obj.Detection.Data.(obj.DetectionToPlot{DTP}) = Loaded.(obj.DetectionToPlot{DTP});
                                end
                            end
                            obj.Reprocessing = true;
                            obj.ExclusionRanges = Loaded.ExclusionRanges;
                        end
                    end
                    if ~obj.Reprocessing
                        obj.ExclusionRanges = [];
                    end
                else
                    return
                end
                
                % Plot a frame
                obj.Reader = VideoReader(Movie);
                obj.Reader.CurrentTime = 10;
                delete(obj.Handles.Player.Axes.Children(:))
                obj.Handles.Player.Plot = image(obj.Reader.readFrame,'Parent',obj.Handles.Player.Axes);
                obj.Parameters.FrameRate = obj.Reader.FrameRate;
                obj.Parameters.Speed.Step = round(obj.Parameters.FrameRate*obj.Parameters.Speed.StepBase);

                % Adjust limits to preserve ratio
                if obj.Reader.Width/obj.Reader.Height >= obj.Handles.Player.AbsolutePosition(3)/obj.Handles.Player.AbsolutePosition(4),
                    % Y needs to be adjusted
                    YDelta = obj.Reader.Width*obj.Handles.Player.AbsolutePosition(4)/obj.Handles.Player.AbsolutePosition(3) - obj.Reader.Height;
                    obj.Handles.Player.Axes.YLim = [1-0.5*YDelta obj.Reader.Height+0.5*YDelta];
                    obj.Handles.Player.Axes.XLim = [1 obj.Reader.Width];
               else
                    % X needs to be adjusted
                    XDelta = obj.Reader.Height*obj.Handles.Player.AbsolutePosition(3)/obj.Handles.Player.AbsolutePosition(4) - obj.Reader.Width;
                    obj.Handles.Player.Axes.XLim = [1-0.5*XDelta obj.Reader.Width+0.5*XDelta];
                    obj.Handles.Player.Axes.YLim = [1 obj.Reader.Height];
                end
                 obj.Handles.Player.Axes.YDir = 'reverse';
                 
                 % Adapt zoom to ratio
                 obj.ZoomValue = [obj.Reader.Width/obj.Reader.Height 1] * obj.Parameters.PxCmRatio * obj.PlotParameters.MouseSpace;
                 
                 
                % EPM special case: we need to plot the ClosedArms to make the difference
                % between open and closed arms, and to process rearing
                if contains(Basename,'EPM')
                    % Check whether it was already saved
                    if ~obj.ReplotArms && isfield(Tracking.(obj.Key).Parameters,'ClosedArms') && ~isfield(Tracking.(obj.Key).Parameters.ClosedArms,'Position') % Legacy
                        obj.ClosedArmVertices{1} = Tracking.(obj.Key).Parameters.ClosedArms.Surf.Position{1};
                        obj.ClosedArmVertices{2} = Tracking.(obj.Key).Parameters.ClosedArms.Surf.Position{2};
                        obj.WallVerticesVertices = Tracking.(obj.Key).Parameters.ClosedArms.Wall.Position;
                    else
                        obj.Handles.DrawClosed1_Button = uicontrol('Style','pushbutton',...
                            'Units','Normalized','Position',[0.065 0.95 0.1 0.04],...
                            'String','Draw closed arm #1',...
                            'FontSize', obj.FontScaling *13,'FontName','Arial','FontWeight','b',...
                            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
                            'HorizontalAlignment','center',...
                            'Callback',{@(~,~)obj.DrawClosed1CB},...
                            'Enable','on');
                        obj.Handles.DrawClosed2_Button = uicontrol('Style','pushbutton',...
                            'Units','Normalized','Position',[0.165 0.95 0.1 0.04],...
                            'String','Draw closed arm #2',...
                            'FontSize', obj.FontScaling *13,'FontName','Arial','FontWeight','b',...
                            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
                            'HorizontalAlignment','center',...
                            'Callback',{@(~,~)obj.DrawClosed2CB},...
                            'Enable','on');
                        obj.Handles.DrawWallVertices_Button = uicontrol('Style','pushbutton',...
                            'Units','Normalized','Position',[0.265 0.95 0.1 0.04],...
                            'String','Draw walls vertices',...
                            'FontSize', obj.FontScaling *13,'FontName','Arial','FontWeight','b',...
                            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
                            'HorizontalAlignment','center',...
                            'Callback',{@(~,~)obj.DrawWallVerticesCB},...
                            'Enable','on');
                        obj.Handles.ValidateArms_Button = uicontrol('Style','pushbutton',...
                            'Units','Normalized','Position',[0.365 0.95 0.075 0.04],...
                            'String','Validate',...
                            'FontSize', obj.FontScaling *13,'FontName','Arial','FontWeight','b',...
                            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
                            'HorizontalAlignment','center',...
                            'Callback',{@(~,~)obj.LoadSession('EPM_Reload')},...
                            'Enable','on');
                        
                        
                        return 
                    end
                elseif contains(Basename,'LDB')
                    % LDB special case: we need to plot the middle walls and to process rearing
                    % Check whether it was already saved
                    if ~obj.ReplotArms && isfield(Tracking.(obj.Key).Parameters,'MiddleWall') 
                        obj.WallVertices = Tracking.(obj.Key).Parameters.MiddleWall.Wall.Position;
                    else
                        Reader = VideoReader([Path  Basename '_IR.mj2']);
                        Reader.CurrentTime = 10;
                        delete(obj.Handles.Player.Axes.Children(:))
                        obj.Handles.Player.Plot = imagesc(Reader.readFrame,'Parent',obj.Handles.Player.Axes);
                        obj.Handles.Player.Clim = [10 50];
                        obj.Handles.DrawClosed1_Button = uicontrol('Style','pushbutton',...
                            'Units','Normalized','Position',[0.065 0.95 0.1 0.04],...
                            'String','Draw wall #1',...
                            'FontSize', obj.FontScaling *13,'FontName','Arial','FontWeight','b',...
                            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
                            'HorizontalAlignment','center',...
                            'Callback',{@(~,~)obj.DrawWall1CB},...
                            'Enable','on');
                        obj.Handles.DrawClosed2_Button = uicontrol('Style','pushbutton',...
                            'Units','Normalized','Position',[0.165 0.95 0.1 0.04],...
                            'String','Draw wall #2',...
                            'FontSize', obj.FontScaling *13,'FontName','Arial','FontWeight','b',...
                            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
                            'HorizontalAlignment','center',...
                            'Callback',{@(~,~)obj.DrawWall2CB},...
                            'Enable','on');
                        obj.Handles.ValidateArms_Button = uicontrol('Style','pushbutton',...
                            'Units','Normalized','Position',[0.265 0.95 0.075 0.04],...
                            'String','Validate',...
                            'FontSize', obj.FontScaling *13,'FontName','Arial','FontWeight','b',...
                            'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[0.6 0.6 0.6],...
                            'HorizontalAlignment','center',...
                            'Callback',{@(~,~)obj.LoadSession('LDB_Reload')},...
                            'Enable','on');
                        
                        obj.Handles.Player.Axes.CLim = [25 50];
                        
                         % Add a small UI to change the contrast
                        obj.Handles.CLimSlider_Axes = axes('Units','normalized',...
                            'Position',[0.35 0.95 0.1 0.04],...
                            'Color',[0.25,0.25,0.25],'LineWidth',1); hold on;
                        obj.Handles.CLimSlider_BaseLine = plot([0 255],[0 0],...
                            'Parent',obj.Handles.CLimSlider_Axes,...
                            'LineWidth',1.5,'Color','k');
                        obj.Handles.CLimSlider_SliderLow = plot(25*[1 1],[-1 1],...
                            'Parent',obj.Handles.CLimSlider_Axes,...
                            'LineWidth',3,'Color','k',...
                            'ButtonDownFcn',@(~,~)obj.CLimSliderLowCB);
                        obj.Handles.CLimSlider_SliderHigh = plot(50*[1 1],[-1 1],...
                            'Parent',obj.Handles.CLimSlider_Axes,...
                            'LineWidth',3,'Color','k',...
                            'ButtonDownFcn',@(~,~)obj.CLimSliderHighCB);
                        obj.Handles.CLimSlider_Axes.XAxis.Visible = 'off';
                        obj.Handles.CLimSlider_Axes.YAxis.Visible = 'off';
                        obj.Handles.CLimSlider_Axes.XLim = [0 255];
                        obj.Handles.CLimSlider_Axes.YLim = [-1.5 1.5];
                        obj.Handles.CLimSlider_Axes.Toolbar.Visible = 'off';
                        disableDefaultInteractivity(obj.Handles.CLimSlider_Axes);
                        return
                    end
                end
            elseif strcmpi(Mode,'EPM_Reload')
                % Check that we have our two areas...
                if isempty(obj.ClosedArmMask{2}) || isempty(obj.ClosedArmMask{1})
                   return 
                end
                delete(obj.Handles.DrawClosed1_Button)
                delete(obj.Handles.DrawClosed2_Button)
                delete(obj.Handles.DrawWallVertices_Button)
                delete(obj.Handles.ValidateArms_Button)
                delete(obj.Handles.ClosedArm(1))
                delete(obj.Handles.ClosedArm(2))
                delete(obj.Handles.WallVertices)
                
                % We need to save the ClosedArms limits for later
                TrackingFile = [obj.Path  obj.Basename '_Tracking.mat'];
                Tracking = load(TrackingFile);
                Tracking.(obj.Key).Parameters.ClosedArms.Surf.Mask{1} = obj.ClosedArmMask{1};
                Tracking.(obj.Key).Parameters.ClosedArms.Surf.Mask{2} = obj.ClosedArmMask{2};
                Tracking.(obj.Key).Parameters.ClosedArms.Surf.Position{1} = obj.ClosedArmVertices{1};
                Tracking.(obj.Key).Parameters.ClosedArms.Surf.Position{2} = obj.ClosedArmVertices{2};
                Tracking.(obj.Key).Parameters.ClosedArms.Wall.Position = obj.WallVerticesVertices;
                Tracking.(obj.Key).Parameters.ClosedArms.Wall.Mask = obj.WallVerticesMask;
                if isfield(Tracking.(obj.Key).Parameters.ClosedArms,'Position')
                    Tracking.(obj.Key).Parameters.ClosedArms = rmfield(Tracking.(obj.Key).Parameters.ClosedArms,'Position');
                end
                save(TrackingFile,'-struct','Tracking')
            elseif strcmpi(Mode,'LDB_Reload')
                 % Check that we have our two areas...
                if isempty(obj.WallMask{2}) || isempty(obj.WallMask{1})
                   return 
                end
                delete(obj.Handles.DrawClosed1_Button)
                delete(obj.Handles.DrawClosed2_Button)
                delete(obj.Handles.ValidateArms_Button)
                delete(obj.Handles.Wall(1))
                delete(obj.Handles.Wall(2))
                delete(obj.Handles.CLimSlider_Axes)
                delete(obj.Handles.Player.Axes.Children(:))
                obj.Handles.Player.Plot = image(obj.Reader.readFrame,'Parent',obj.Handles.Player.Axes);
                
                % We need to save the ClosedArms limits for later
                TrackingFile = [obj.Path  obj.Basename '_Tracking.mat'];
                Tracking = load(TrackingFile);
                Tracking.(obj.Key).Parameters.MiddleWall.Wall.Position = obj.WallVertices;
                Tracking.(obj.Key).Parameters.MiddleWall.Wall.Mask = obj.WallMask;
                save(TrackingFile,'-struct','Tracking')
                obj.Handles.Player.Axes.CLim = [0 255];
            end
            
            % Plot closed arms limits (redundant but it's also to
            % double-check everything is OK)
            if contains(obj.Basename,'EPM')
                obj.Handles.ClosedArm(1) = drawpolygon('Position',obj.ClosedArmVertices{1},'Color','c','FaceAlpha',0.05,'LineWidth',0.5,'Deletable',false,'InteractionsAllowed','none');
                obj.Handles.ClosedArm(2) = drawpolygon('Position',obj.ClosedArmVertices{2},'Color','c','FaceAlpha',0.05,'LineWidth',0.5,'Deletable',false,'InteractionsAllowed','none');
                obj.Handles.WallVertices = plot(obj.WallVerticesVertices(:,1),obj.WallVerticesVertices(:,2),'co','MarkerFaceColor','c','MarkerEdgeColor','k','LineWidth',0.5);               
            elseif contains(obj.Basename,'LDB')
                obj.Handles.Wall(1) = drawpolygon('Position',obj.WallVertices{1},'Color','c','FaceAlpha',0.05,'LineWidth',0.5,'Deletable',false,'InteractionsAllowed','none');
                obj.Handles.Wall(2) = drawpolygon('Position',obj.WallVertices{2},'Color','c','FaceAlpha',0.05,'LineWidth',0.5,'Deletable',false,'InteractionsAllowed','none');
                obj.Handles.WallVertices(1) = plot(obj.WallVertices{1}(:,1),obj.WallVertices{1}(:,2),'co','MarkerFaceColor','c','MarkerEdgeColor','k','LineWidth',0.5);               
                obj.Handles.WallVertices(2) = plot(obj.WallVertices{2}(:,1),obj.WallVertices{2}(:,2),'co','MarkerFaceColor','c','MarkerEdgeColor','k','LineWidth',0.5);               
            end

            obj.Handles.SessionName = uicontrol('Style','text',...
                'Units','Normalized','Position',[0.05 0.95 0.25 0.025],...
                'BackgroundColor',[0.25,0.25,0.25],...
                'String',obj.Basename,...
                'FontSize', obj.FontScaling *14,'FontName','Arial','FontWeight','b',...
                'HorizontalAlignment','left');
            
            % Load DLC tracking
            DLCFile = obj.File;
            FO = fopen(DLCFile);
            fgetl(FO);
            Bodyparts = strsplit(fgetl(FO),',');
            Bodyparts = unique(Bodyparts(2:end),'stable');
            fclose(FO);
            DLCTracking = csvread(DLCFile,3,0);
            % Rearrange the points by body parts, as two columns
            for B = 1 : numel(Bodyparts)
                obj.Coordinates.(Bodyparts{B}) = [DLCTracking(:,2+(B-1)*3),DLCTracking(:,3+(B-1)*3)]+1;
                obj.Score.(Bodyparts{B}) = DLCTracking(:,4+(B-1)*3);
            end
            obj.Bodyparts = Bodyparts;
            if strcmpi(obj.EnabledBodyparts{1},'all')
                obj.EnabledBodypartsIndex = 1:numel(Bodyparts);
            else
                BPIndex = [];
                for BPin = 1 : numel(obj.EnabledBodyparts)
                    if any(strcmpi(Bodyparts,obj.EnabledBodyparts{BPin}))
                        BPIndex = [BPIndex;unique(find(strcmpi(Bodyparts,obj.EnabledBodyparts{BPin})))];
                    else
                        warning(['Requested bodypart ' obj.EnabledBodyparts{BPin} ' is not a valid bodypart name.'])
                    end
                end
                obj.EnabledBodypartsIndex = BPIndex;
            end
            
            obj.CurrentTime = obj.Reader.CurrentTime;
            
            % Run algorithm and plot
            obj.RunAlgorithm;
        end
        
        
        
        function CLimSliderLowCB(obj)
            if ~obj.Dragging
                obj.Dragging = true;
                obj.Handles.MainFigure.WindowButtonMotionFcn = {@(~,~)obj.MovingLowCLim};
                obj.Handles.MainFigure.WindowButtonUpFcn = {@(~,~)obj.CLimSliderLowCB};
            else
                obj.Dragging = false;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
            end
        end
        
        function MovingLowCLim(obj)
            CurrentCursor = round(obj.Handles.CLimSlider_Axes.CurrentPoint(1));
            if CurrentCursor>=0 && CurrentCursor<=255 && obj.Handles.Player.Axes.CLim(2)>CurrentCursor
                obj.Handles.Player.Axes.CLim(1) = CurrentCursor;
                obj.Handles.CLimSlider_SliderLow.XData = [CurrentCursor CurrentCursor];
                drawnow
            elseif CurrentCursor<0
                obj.Handles.Player.Axes.CLim(1) = 0;
                obj.Handles.CLimSlider_SliderLow.XData = [0 0];
                drawnow
            end
        end
        
       
        function CLimSliderHighCB(obj)
            if ~obj.Dragging
                obj.Dragging = true;
                obj.Handles.MainFigure.WindowButtonMotionFcn = {@(~,~)obj.MovingHighCLim};
                obj.Handles.MainFigure.WindowButtonUpFcn = {@(~,~)obj.CLimSliderHighCB};
            else
                obj.Dragging = false;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
            end
        end
        
        function MovingHighCLim(obj)
            CurrentCursor = round(obj.Handles.CLimSlider_Axes.CurrentPoint(1));
            if CurrentCursor>=0 && CurrentCursor<=255 && obj.Handles.Player.Axes.CLim(1)<CurrentCursor
                obj.Handles.Player.Axes.CLim(2) = CurrentCursor;
                obj.Handles.CLimSlider_SliderHigh.XData = [CurrentCursor CurrentCursor];
                drawnow
            elseif CurrentCursor>255
                obj.Handles.Player.Axes.CLim(2) = 255;
                obj.Handles.CLimSlider_SliderHigh.XData = [255 255];
                drawnow
            end
        end
        
        function SliderCB(obj,src,~)
            if ~obj.Dragging
                if ~isempty(obj.Reader)
                    obj.Dragging = true;
                    obj.CurrentPlayingStatus = obj.Playing;
                    obj.Playing = false;
                    obj.CurrentAxis = src.Parent;
                    obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingSlider;
                    obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.SliderCB;
                end
            else
                obj.Dragging = false;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
                obj.Playing = obj.CurrentPlayingStatus;
                if obj.CurrentPlayingStatus
                    obj.CurrentTime = obj.Handles.DetectionPlots_TimeLine(1).XData(1);
                    obj.Play_CB('Resume');
                else
                    obj.CurrentTime = obj.Handles.DetectionPlots_TimeLine(1).XData(1);
                    obj.PlayMovies('Slider');
                end
            end
        end
        
        function MovingSlider(obj,src)
            CurrentCursor = obj.CurrentAxis.CurrentPoint;
            if CurrentCursor(1)>=0 && CurrentCursor(1)<=obj.Reader.Duration
                for F = numel(obj.Measurements.ToPlot) : -1 : 1
                    obj.Handles.MeasurementsPlots_TimeLine(F).XData = CurrentCursor(1)*[1;1];
                end
                for F = numel(obj.Detection.ToPlot) : -1 : 1
                    obj.Handles.DetectionPlots_TimeLine(F).XData = CurrentCursor(1)*[1;1];
                end
                obj.Handles.UIElements.CurrentTimeEdit.String = num2str(1/100 * round(CurrentCursor(1)*100),'%.2f');
            else
                return
            end

            if ~obj.Refractory 
                obj.Refractory = true;
                obj.CurrentTime = CurrentCursor(1);
                obj.PlayMovies('Slider');
                obj.Refractory = false;
            end
        end
        
        function Play_CB(obj,Mode,varargin)
            TimedPause = false;
            if nargin == 1
                Mode = [];
            end
            if strcmpi(Mode,'Timed')
                EndTime = varargin{1};
                Mode = [];
                TimedPause = true;
            else
                EndTime = inf;
            end
            if ~isempty(obj.Reader)
                if obj.Playing && isempty(Mode)
                    obj.Playing = false;
%                     clear sound
                    obj.Handles.UIElements.PlayButton.String = 'Play';
                    obj.PlayMovies;
                else
                    obj.Playing = true;
                    TicPlayer = tic;
                    obj.Handles.UIElements.PlayButton.String = 'Pause';
                    obj.PlayMovies;
%                     InitSound = false;
%                     LastTickSound = TicPlayer;
                    while obj.Playing && obj.CurrentTime <= EndTime
                        TocPlayer = toc(TicPlayer);
                        TicPlayer = tic;
                        obj.CurrentTime = obj.CurrentTime + TocPlayer * obj.PlayRate;
%                         if ~InitSound || (toc(LastTickSound) * obj.PlayRate) > 5
%                             IndxSound = FindInInterval(obj.SoundTimes,[obj.CurrentTime obj.CurrentTime+5]+0.1);
%                             clear sound
%                             sound(obj.Sound(IndxSound:end),obj.SoundFrequency * obj.PlayRate);
%                             LastTickSound = tic;
%                             InitSound = true;
%                         end
                        obj.PlayMovies;
                    end
                    if TimedPause
                        obj.Handles.UIElements.PlayButton.String = 'Play';
                        obj.Playing = false;
                    end
                end
            end
        end
        
        function Slower_CB(obj)
            if (obj.PlayRate / 2) >= 0.125
                obj.PlayRate = obj.PlayRate / 2;
                obj.Handles.UIElements.PlayRateLegend.String = ['x' num2str(1/1000 * round(obj.PlayRate*1000))];
            end
        end
        
        function Faster_CB(obj)
            if (obj.PlayRate / 2) <= 128
                obj.PlayRate = obj.PlayRate * 2;
                obj.Handles.UIElements.PlayRateLegend.String  = ['x' num2str(1/100 * round(obj.PlayRate*100))];
            end
        end
        
        function PlayMovies(obj,Param)
            if nargin == 1
                Param = [];
            end
            if ~isempty(obj.Reader)
                CTime = obj.CurrentTime;
                obj.CurrentTimeLast = CTime;
                if strcmpi(Param,'Slider')
                    SliderUpdate = false;
                else
                    SliderUpdate = true;
                end
                DLCIndex =  FindInInterval(obj.Times,[CTime CTime]);
                if ~isempty(DLCIndex)
                    DLCIndex = DLCIndex(1);
                end
                if ~isempty(DLCIndex) && obj.Times(DLCIndex)-1/1000<=obj.Reader.Duration
                    if SliderUpdate
                        obj.Handles.UIElements.CurrentTimeEdit.String = num2str(1/100 * round(obj.Times(DLCIndex)*100),'%.2f');
                    end
                    if obj.PlayingSingle
                        obj.PlayingSingle = false;
                    end
                    if SliderUpdate
                        for F = numel(obj.Measurements.ToPlot) : -1 : 1
                            obj.Handles.MeasurementsPlots_TimeLine(F).XData = CTime*[1;1];
                        end
                        for F = numel(obj.Detection.ToPlot) : -1 : 1
                            obj.Handles.DetectionPlots_TimeLine(F).XData = CTime*[1;1];
                        end
                    end
                    if strcmpi(Param,'Initialize')
                        % Contour
                        if obj.Enabled.Contour
                            obj.Handles.Contour = plot(obj.Coordinates.Contour{DLCIndex}(1,:),obj.Coordinates.Contour{DLCIndex}(2,:),'Color',obj.PlotParameters.MouseContourColor,'Linewidth',2.5,'Parent',obj.Handles.Player.Axes);
                        else
                            obj.Handles.Contour = plot(NaN,NaN,'Color',obj.PlotParameters.MouseContourColor,'Linewidth',2,'Parent',obj.Handles.Player.Axes);
                        end
                        if ~isempty(obj.EnabledBodypartsIndex)
                            % We need to create the bodyparts
                            for BP = obj.EnabledBodypartsIndex
                                if ~isfield(obj.PlotParameters.MarkersInnerColor,obj.Bodyparts{BP})
                                    obj.PlotParameters.MarkersInnerColor.(obj.Bodyparts{BP}) = obj.PlotParameters.MarkersInnerColor.All;
                                end
                                if ~isfield(obj.PlotParameters.MarkersOuterColor,obj.Bodyparts{BP})
                                    obj.PlotParameters.MarkersOuterColor.(obj.Bodyparts{BP}) = obj.PlotParameters.MarkersOuterColor.All;
                                end
                                if ~isfield(obj.PlotParameters.MarkersInnerSize,obj.Bodyparts{BP})
                                    obj.PlotParameters.MarkersInnerSize.(obj.Bodyparts{BP}) = obj.PlotParameters.MarkersInnerSize.All;
                                end
                                if ~isfield(obj.PlotParameters.MarkersOuterSize,obj.Bodyparts{BP})
                                    obj.PlotParameters.MarkersOuterSize.(obj.Bodyparts{BP}) = obj.PlotParameters.MarkersOuterSize.All;
                                end
                                if ~isfield(obj.PlotParameters.MarkersShape,obj.Bodyparts{BP})
                                    obj.PlotParameters.MarkersShape.(obj.Bodyparts{BP}) = obj.PlotParameters.MarkersShape.All;
                                end
                                obj.Handles.BodyParts.(obj.Bodyparts{BP}).W = plot(obj.Coordinates.(obj.Bodyparts{BP})(DLCIndex,1),obj.Coordinates.(obj.Bodyparts{BP})(DLCIndex,2),obj.PlotParameters.MarkersShape.(obj.Bodyparts{BP}),'Color',obj.PlotParameters.MarkersOuterColor.(obj.Bodyparts{BP}),'MarkerSize',obj.PlotParameters.MarkersOuterSize.(obj.Bodyparts{BP}),'LineWidth',3,'Parent',obj.Handles.Player.Axes,'MarkerFaceColor',obj.PlotParameters.MarkersOuterColor.(obj.Bodyparts{BP}));
                                obj.Handles.BodyParts.(obj.Bodyparts{BP}).B = plot(obj.Coordinates.(obj.Bodyparts{BP})(DLCIndex,1),obj.Coordinates.(obj.Bodyparts{BP})(DLCIndex,2),obj.PlotParameters.MarkersShape.(obj.Bodyparts{BP}),'Color',obj.PlotParameters.MarkersInnerColor.(obj.Bodyparts{BP}),'MarkerSize',obj.PlotParameters.MarkersInnerSize.(obj.Bodyparts{BP}),'LineWidth',1.5,'Parent',obj.Handles.Player.Axes,'MarkerFaceColor',obj.PlotParameters.MarkersInnerColor.(obj.Bodyparts{BP}));
                                if ~obj.Enabled.Bodyparts
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.XData = NaN;
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.YData = NaN;
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).B.XData = NaN;
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).B.YData = NaN;   
                                end
                            end
                        end
                        
                        % Center of gravity
                        obj.Handles.CenterG = plot(obj.Coordinates.CenterG(DLCIndex,1),obj.Coordinates.CenterG(DLCIndex,2),'+','Color',obj.PlotParameters.MouseCenterGColor,'MarkerSize',9,'Linewidth',1.5,'Parent',obj.Handles.Player.Axes);
                        if ~obj.Enabled.Center
                            obj.Handles.CenterG.XData = NaN;
                            obj.Handles.CenterG.YData = NaN;
                        end
                    else
                        if ~isempty(obj.EnabledBodypartsIndex)
                            if obj.Enabled.Bodyparts
                                % We update the coordinates
                                for BP = obj.EnabledBodypartsIndex
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.XData = obj.Coordinates.(obj.Bodyparts{BP})(DLCIndex,1);
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.YData = obj.Coordinates.(obj.Bodyparts{BP})(DLCIndex,2);
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).B.XData =  obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.XData;
                                    obj.Handles.BodyParts.(obj.Bodyparts{BP}).B.YData = obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.YData;
                                end
                            end
                        end
                            % Contour
                        if obj.Enabled.Contour
                            obj.Handles.Contour.XData = obj.Coordinates.Contour{DLCIndex}(1,:);
                            obj.Handles.Contour.YData = obj.Coordinates.Contour{DLCIndex}(2,:);
                        else
                            obj.Handles.Contour.XData = NaN;
                            obj.Handles.Contour.YData = NaN;
                        end
                        % Center of gravity
                        if obj.Enabled.Center
                            obj.Handles.CenterG.XData = obj.Coordinates.CenterG(DLCIndex,1);
                            obj.Handles.CenterG.YData = obj.Coordinates.CenterG(DLCIndex,2);
                        else
                            obj.Handles.CenterG.XData = NaN;
                            obj.Handles.CenterG.YData = NaN;
                        end
                        
                        % Area explored
                        if obj.Enabled.AreaBound 
                            obj.Handles.AreaExploredK.XData = obj.Measurements.Data.BoundingBox{DLCIndex}([1:4 1],1);
                            obj.Handles.AreaExploredK.YData = obj.Measurements.Data.BoundingBox{DLCIndex}([1:4 1],2);
                            obj.Handles.AreaExploredW.XData = obj.Measurements.Data.BoundingBox{DLCIndex}([1:4 1],1);
                            obj.Handles.AreaExploredW.YData = obj.Measurements.Data.BoundingBox{DLCIndex}([1:4 1],2);
                        else
                            obj.Handles.AreaExploredK.XData = NaN;
                            obj.Handles.AreaExploredK.YData = NaN;
                            obj.Handles.AreaExploredW.XData = NaN;
                            obj.Handles.AreaExploredW.YData = NaN;
                        end
                        
                        for DT = 1 : numel(obj.Detection.ToPlot)
                            if obj.Detection.Logical.(obj.Detection.ToPlot{DT})(DLCIndex) && obj.Enabled.DetectionVisual && ~contains(obj.ExcludePlot,obj.Detection.ToPlot{DT})
                                obj.Handles.OverlayDetection(DT).Visible = 'on';
                            else
                                obj.Handles.OverlayDetection(DT).Visible = 'off';
                            end
                        end
                    end
                    obj.Reader.CurrentTime = obj.Times(DLCIndex)-1/1000;
                    obj.Handles.Player.Plot.CData = obj.Reader.readFrame;
                else
                    obj.Playing = false;
                    obj.Handles.UIElements.PlayButton.String = 'Play';
                    obj.CurrentTime = 0;
                    DLCIndex = 1;
                    obj.Handles.UIElements.CurrentTimeEdit.String = num2str(1/100 * round(obj.CurrentTime*100),'%.2f');
                end
                if CTime>=obj.Handles.DetectionAxes(1).XLim(2)-0.1*diff(obj.Handles.DetectionAxes(1).XLim) &&  CTime<(obj.Times(end)-0.1*diff(obj.Handles.DetectionAxes(1).XLim))
                    obj.Handles.DetectionAxes(1).XLim = obj.Handles.DetectionAxes(1).XLim + 0.75 * diff(obj.Handles.DetectionAxes(1).XLim);
%                       obj.Handles.DetectionAxes(1).XLim = CTime + 0.5*diff(obj.Handles.DetectionAxes(1).XLim)*[-1 1] ;
                end
                
                if obj.Enabled.Zoom && ~isnan(obj.Coordinates.CenterG(DLCIndex,1))
                    obj.Handles.Player.Axes.XLim = obj.Coordinates.CenterG(DLCIndex,1) + [-1 1]*obj.ZoomValue(1);
                    obj.Handles.Player.Axes.YLim = obj.Coordinates.CenterG(DLCIndex,2) + [-1 1]*obj.ZoomValue(2);
                end
                drawnow
            end
        end
        
        function CurrentTime_CB(obj)
            InputTime = str2double(obj.Handles.UIElements.CurrentTimeEdit.String);
            if ~isempty(InputTime) && InputTime <= obj.Reader.Duration
                obj.CurrentTime = InputTime;
                obj.PlayingSingle = true;
                obj.PlayMovies;
            end
        end
        
        
        
        
        % Algorithm: can be called from the command line after
        % manually editing its code when adding more stuff
        function RunAlgorithm(obj)
            obj.Detection.ToPlot = obj.DetectionToPlot;
            if strcmpi(obj.Key,'RGB')
                obj.Measurements.ToPlot = {'Motion','StepSpeed','Grooming','TailMotion','TotalLength'};
            else
                obj.Measurements.ToPlot = {'Motion','StepSpeed','Grooming','TotalLength'};
            end
            for Md = 1 : numel(obj.MeasurementsToPlot)
                if ~any(strcmpi(obj.Measurements.ToPlot,obj.MeasurementsToPlot{Md}))
                    obj.Measurements.ToPlot = [obj.Measurements.ToPlot, obj.MeasurementsToPlot{Md}];
                end
            end

            % Get mouse speeds
            FilteredCenterG = smoothdata(obj.Coordinates.CenterG,1,'movmedian',10);
            Distances = NaN(size(obj.Coordinates.CenterG,1),1);
            Speed = NaN(size(obj.Coordinates.CenterG,1),1);
            for S = 2:numel(FilteredCenterG(:,1))
                Distances(S) = (realsqrt((FilteredCenterG(S,1)-FilteredCenterG(S-1,1))^2 + (FilteredCenterG(S,2)-FilteredCenterG(S-1,2))^2))/obj.Parameters.PxCmRatio;
            end
            for S = 2+obj.Parameters.Speed.Step:numel(FilteredCenterG(:,1))
                Speed(S) = sum(Distances(S-obj.Parameters.Speed.Step:S))/((obj.Parameters.Speed.Step+1) / obj.Reader.FrameRate);
            end
            obj.Measurements.Data.Speed = Speed;
            
            StepSpeed = NaN(size(obj.Coordinates.CenterG,1),1);
            for S = 2+obj.Parameters.Speed.Step:numel(FilteredCenterG(:,1))
                StepSpeed(S) = (realsqrt((FilteredCenterG(S,1)-FilteredCenterG(S-obj.Parameters.Speed.Step,1))^2 + (FilteredCenterG(S,2)-FilteredCenterG(S-obj.Parameters.Speed.Step,2))^2))/(obj.Parameters.PxCmRatio*(obj.Parameters.Speed.Step+1) / obj.Reader.FrameRate);
            end
            obj.Measurements.Data.StepSpeed = StepSpeed;

            %% Preprocessing / data preparation
            % We want to process only what we need
            ProcessedSpeeds = {obj.Parameters.TailRattling.Reference,obj.Parameters.TailRattling.Motion};
            if any(contains(obj.Measurements.ToPlot,'Speed'))
                IndxTP = find(contains(obj.Measurements.ToPlot,'Speed'));
                for C = 1 : numel(IndxTP)
                    if ~(strcmpi(obj.Measurements.ToPlot{IndxTP(C)},'Speed') || strcmpi(obj.Measurements.ToPlot{IndxTP(C)},'StepSpeed'))
                    BPtoAdd = strsplit(obj.Measurements.ToPlot{IndxTP(C)},'Speed');
                    ProcessedSpeeds = [ProcessedSpeeds, BPtoAdd{end}];
                    end
                end
            end
            Bodyparts = obj.Bodyparts;
            for B = 1 : numel(Bodyparts),
                obj.Coordinates.(Bodyparts{B})(obj.Score.(Bodyparts{B})<0.95 | any(obj.Coordinates.(Bodyparts{B})<=1,2) | (obj.Coordinates.(Bodyparts{B})(:,2)>=479)  | (obj.Coordinates.(Bodyparts{B})(:,1)>=639) ,:) = NaN;
                if any(contains(ProcessedSpeeds,Bodyparts{B})),
                    FilteredCoorG = smoothdata(obj.Coordinates.(Bodyparts{B}),1,'movmedian',1);
                    obj.Measurements.Data.(Bodyparts{B}).Distance = NaN(size(FilteredCoorG,1),1);
                    for S = 2:numel(FilteredCoorG(:,1))
                        obj.Measurements.Data.(Bodyparts{B}).Distance(S) = (realsqrt((FilteredCoorG(S,1)-FilteredCoorG(S-1,1))^2 + (FilteredCoorG(S,2)-FilteredCoorG(S-1,2))^2))/obj.Parameters.PxCmRatio;
                    end
                    obj.Measurements.Data.(Bodyparts{B}).Speed = NaN(size(FilteredCoorG,1),1);
                    for S = 2+obj.Parameters.Speed.Step:numel(FilteredCoorG(:,1))
                        obj.Measurements.Data.(Bodyparts{B}).Speed(S) = sum(obj.Measurements.Data.(Bodyparts{B}).Distance(S-obj.Parameters.Speed.Step:S))/((obj.Parameters.Speed.Step+1) / obj.Reader.FrameRate);
                    end
                    obj.Measurements.Data.(Bodyparts{B}).StepSpeed = NaN(size(FilteredCoorG,1),1);
                    for S = 2+obj.Parameters.Speed.Step:numel(FilteredCoorG(:,1))
                        obj.Measurements.Data.(Bodyparts{B}).StepSpeed(S) = (realsqrt((FilteredCoorG(S,1)-FilteredCoorG(S-obj.Parameters.Speed.Step,1))^2 + (FilteredCoorG(S,2)-FilteredCoorG(S-obj.Parameters.Speed.Step,2))^2))/(obj.Parameters.PxCmRatio*(obj.Parameters.Speed.Step+1) / obj.Reader.FrameRate);
                    end
                end
            end
            

            % Mid-ears point
            MidEars_Points = (cell2mat(arrayfun(@(x) (obj.Coordinates.EarLeft(x,:)+0.5*(obj.Coordinates.EarRight(x,:)-obj.Coordinates.EarLeft(x,:)))',1:size(obj.Coordinates.EarLeft,1),'UniformOutput',false)))';
            
            % Bodyparts distances
            MidEars_CenterG_Distance = (1/obj.Parameters.PxCmRatio * arrayfun(@(x) Distance2D(MidEars_Points(x,:),obj.Coordinates.CenterG(x,:)),1:size(MidEars_Points,1)))';
            obj.Measurements.Data.MidEars_CenterG_Distance = smoothdata(MidEars_CenterG_Distance,'gaussian',1);
            MidEars_Snout_Distance = (1/obj.Parameters.PxCmRatio * arrayfun(@(x) Distance2D(MidEars_Points(x,:),obj.Coordinates.Snout(x,:)),1:size(MidEars_Points,1)))';
%             NaNIndex = isnan(MidEars_Snout_Distance);
            MidEars_Snout_Distance = smoothdata(MidEars_Snout_Distance,'gaussian',obj.Parameters.Smoothing);
%             MidEars_Snout_Distance(NaNIndex) = NaN;
            obj.Measurements.Data.MidEars_Snout_Distance = MidEars_Snout_Distance;
            
            MidEars_TailBase_Distance = (1/obj.Parameters.PxCmRatio * arrayfun(@(x) Distance2D(MidEars_Points(x,:),obj.Coordinates.TailBase(x,:)),1:size(MidEars_Points,1)))';
            %             NaNIndex = isnan(MidEars_TailBase_Distance);
            MidEars_TailBase_Distance = smoothdata(MidEars_TailBase_Distance,'gaussian',obj.Parameters.Smoothing);
            %             MidEars_TailBase_Distance(NaNIndex) = NaN;
            obj.Measurements.Data.MidEars_TailBase_Distance = MidEars_TailBase_Distance;
            
            Tailbase_CenterG_Distance = (1/obj.Parameters.PxCmRatio * arrayfun(@(x) Distance2D(obj.Coordinates.TailBase(x,:),obj.Coordinates.CenterG(x,:)),1:size(obj.Coordinates.TailBase,1)))';
            TotalLength = Tailbase_CenterG_Distance + MidEars_CenterG_Distance;
            TotalLength(isnan(Tailbase_CenterG_Distance)) = NaN;
            TotalLength(isnan(MidEars_CenterG_Distance)) = NaN;
            obj.Measurements.Data.TotalLength = (smoothdata(TotalLength,'gaussian',obj.Parameters.Smoothing));


            % Tail total length
            if any(contains(obj.Measurements.ToPlot,'TailLength'))
                TailLength = NaN(size(obj.Coordinates.TailBase,1),1);
                for TB = 1 : size(obj.Coordinates.TailBase,1)
                    TailLength(TB) = Distance2D(obj.Coordinates.TailBase(TB,:),obj.Coordinates.TailQuarterAnt(TB,:)) +...
                        Distance2D(obj.Coordinates.TailQuarterAnt(TB,:),obj.Coordinates.TailMiddle(TB,:)) +...
                        Distance2D(obj.Coordinates.TailMiddle(TB,:),obj.Coordinates.TailQuarterPost(TB,:)) +...
                        Distance2D(obj.Coordinates.TailQuarterPost(TB,:),obj.Coordinates.TailEnd(TB,:));
                end
                obj.Measurements.Data.TailLength = 1/obj.Parameters.PxCmRatio * TailLength;
            end
            
            % Get a hindpaw score
            Vector1 = [0 1 0];
            RotatedHindPawRight = NaN( size(obj.Coordinates.TailBase,1),2);
            RotatedHindPawLeft = NaN( size(obj.Coordinates.TailBase,1),2);
            for TB = 1 : size(obj.Coordinates.TailBase,1)
                if obj.Score.HindPawLeft(TB)>=0.99 || obj.Score.HindPawRight(TB)>=0.99
                    if obj.Score.TailBase(TB)>=0.99
                        Vector2 = ([obj.Coordinates.CenterG(TB,:) - obj.Coordinates.TailBase(TB,:) 0])/norm([obj.Coordinates.CenterG(TB,:) - obj.Coordinates.TailBase(TB,:) 0]);
                        x = cross(Vector1,Vector2);
                        c = sign(dot(x,[0 0 1])) * norm(x);
                        RadAngle = atan2(c,dot(Vector1,Vector2));
                        Rz = [cos(RadAngle) sin(RadAngle) ; -sin(RadAngle) cos(RadAngle)] ;
                        if obj.Score.HindPawLeft(TB)>=0.99
                            CenteredHPL = obj.Coordinates.HindPawLeft(TB,:) - obj.Coordinates.TailBase(TB,:);
                            RotatedHindPawLeft(TB,:) = Rz*(CenteredHPL)';
                        else
                            RotatedHindPawLeft(TB,:) = [NaN NaN];
                        end
                        if obj.Score.HindPawRight(TB)>=0.99
                            CenteredHPR = obj.Coordinates.HindPawRight(TB,:) - obj.Coordinates.TailBase(TB,:);
                            RotatedHindPawRight(TB,:) = Rz*(CenteredHPR)';
                        else
                            RotatedHindPawRight(TB,:) = [NaN NaN];
                        end
                    end
                end
            end
            
            obj.Measurements.Data.HindPawLeft = RotatedHindPawLeft(:,2)/obj.Parameters.PxCmRatio;
            obj.Measurements.Data.HindPawRight = RotatedHindPawRight(:,2)/obj.Parameters.PxCmRatio;
            
            % MidBody
            MidBodyLength = NaN(size(obj.Coordinates.TailBase,1),1);
            MidBodyAngle = NaN(size(obj.Coordinates.TailBase,1),1);
            
            Score.TailBase = obj.Score.TailBase;
            CenterG = obj.Coordinates.CenterG;
            Coordinates.TailBase = obj.Coordinates.TailBase;
            Contour = obj.Coordinates.Contour;
            parfor TB = 1 : size(obj.Coordinates.TailBase,1)
                if Score.TailBase(TB) > 0.9 && ~isnan(MidEars_Points(TB,1))
                    Vector1 = ([CenterG(TB,:) - MidEars_Points(TB,:) 0])/norm([CenterG(TB,:) - MidEars_Points(TB,:) 0]);
                    Vector2 = ([CenterG(TB,:) - Coordinates.TailBase(TB,:) 0])/norm([CenterG(TB,:) - Coordinates.TailBase(TB,:) 0]);
                    x = cross(Vector1,Vector2);
                    c = sign(dot(x,[0 0 1])) * norm(x);
                    MidBodyAngle(TB) = atan2(c,dot(Vector1,Vector2));
                    % Find contour points that best matches the mid-angle
                    TBAngle = zeros(numel(Contour{TB}(:,1)),1);
                    for Pnt = 1 : numel(Contour{TB}(1,:))
                        Vector2 = ([CenterG(TB,:) - (Contour{TB}(:,Pnt))' 0])/norm([CenterG(TB,:) - (Contour{TB}(:,Pnt))' 0]);
                        x = cross(Vector1,Vector2);
                        c = sign(dot(x,[0 0 1])) * norm(x);
                        TBAngle(Pnt) = atan2(c,dot(Vector1,Vector2));
                    end
                    [~, Point1Index] = min(mod(TBAngle-MidBodyAngle(TB)/2,2*pi));
                    [~, Point2Index] = min(mod(TBAngle-(2*pi - MidBodyAngle(TB)/2),2*pi));
                    Point1 = Contour{TB}(:,Point1Index);
                    Point2 = Contour{TB}(:,Point2Index);
                    MidBodyLength(TB) = Distance2D(Point1,Point2);
                end
            end
            
            MidBodyLength = MidBodyLength/obj.Parameters.PxCmRatio;
            obj.Measurements.MidBodyLength = MidBodyLength;
            obj.Measurements.MidBodyAngle = MidBodyAngle;
            
            IndexStMouse = (pi-abs((MidBodyAngle)))<0.4;
            StRatio = TotalLength./MidBodyLength;
            
            obj.Measurements.Data.StRatio = StRatio;
            
            if strcmpi(obj.Key,'RGB')
                % Tail Rattling
                TailMotion = (obj.Measurements.Data.(obj.Parameters.TailRattling.Motion).Speed - obj.Measurements.Data.(obj.Parameters.TailRattling.Reference).Speed);
                TailMotionTimes = obj.Times(~isnan(TailMotion));
                TailMotion = TailMotion(~isnan(TailMotion));
                TargetTS = seconds(obj.Times);
                TT = timetable(duration(0,0,TailMotionTimes,'Format','s'), TailMotion);
                [tt] = synchronize(TT,TargetTS,'linear');
                obj.Measurements.Data.TailMotion = tt.Variables;
                TailRattling = obj.Measurements.Data.TailMotion>obj.Parameters.TailRattling.Threshold & obj.Measurements.Data.StepSpeed<obj.Parameters.TailRattling.MaxStepSpeedBody & obj.Measurements.Data.(obj.Parameters.TailRattling.Reference).StepSpeed < obj.Parameters.TailRattling.MaxStepSpeedMoving;
                if ~obj.Reprocessing
                    obj.Detection.Data.TailRattling = obj.GetRanges(TailRattling,obj.Parameters.TailRattling.Merging,obj.Parameters.TailRattling.MinimumDuration);
                end
                
                BaseArray = false(size(obj.Times));
                DT = find(contains(obj.Detection.ToPlot,'TailRattling'));
                obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                    for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                        Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                        obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                    end
                end
            else
                BaseArray = false(size(obj.Times));
                obj.Detection.Logical.TailRattling = BaseArray;
            end
            
            %% Mouse size
            % Mouse size is actually not so constant...
            % and that's enough to mess with any threshold based on real
            % dimensions: we need a correcting factor
            %
            % We don't use min and max to prevent being contaminated by
            % potential (unlikely) outliers, and not a global mean because
            % it depends on the behaviour displayed (if the mouse is
            % spending a lot of time strech-attending, the mean will be
            % higher than if it is freezing a lot -this will bias the
            % "actual" size of the mouse, and impair the detection down the
            % line
            
            HindPawLeftTemp = obj.Measurements.Data.HindPawLeft;
            HindPawLeftTemp(isnan(HindPawLeftTemp)) = 0;
            HindPawRightTemp = obj.Measurements.Data.HindPawRight;
            HindPawRightTemp(isnan(HindPawRightTemp)) = 0;
%             SupLength = prctile(round(TotalLength((HindPawLeftTemp>0.5 & HindPawRightTemp>0.5) |...
%                 (obj.Score.HindPawRight<0.9 & obj.Score.HindPawLeft<0.9) &...
%                 obj.Measurements.Data.Speed>1.5),2),99.75);
%             disp('SupLength')
%             disp(SupLength)
            SupSnout = prctile(round(MidEars_Snout_Distance.^0.5,2),99.75);
%             disp('SupSnout')
%             disp(SupSnout)
            
            obj.Measurements.Data.Product = (MidEars_Snout_Distance.^0.5).*MidEars_TailBase_Distance;
            obj.Parameters.SizeCorrection = (prctile(TotalLength(StRatio>1.8 & StRatio<2 & IndexStMouse & ...
                ((HindPawLeftTemp>0.5 & HindPawRightTemp>0.5) |...
                (obj.Score.HindPawRight<0.95 & obj.Score.HindPawLeft<0.95))),85))/6.8 * (1+ 0.75*((SupSnout)/1.525-1));
            
            figure(obj.Handles.MainFigure)
            %% Grooming
            if ~obj.Reprocessing
                obj.Parameters.Grooming.Threshold = obj.Parameters.Grooming.BaseThreshold * obj.Parameters.SizeCorrection;
            end
%             disp('SizeCorrection')
%             disp(obj.Parameters.SizeCorrection)
%             disp('Threshold')
%             disp(obj.Parameters.Grooming.Threshold)
            
            obj.Measurements.Data.Grooming = smoothdata(obj.Measurements.Data.Product,'gaussian',40);
            obj.Measurements.Data.Grooming(obj.Measurements.Data.Grooming == 0) = 15;
            IndxGrooming = find(obj.Measurements.Data.Grooming<obj.Parameters.Grooming.Threshold &...
                obj.Measurements.Data.StepSpeed<obj.Parameters.Grooming.MaxStepSpeed &...
                obj.Measurements.Data.Motion>obj.Parameters.Grooming.LowMotion);
            Ranges = FindContinuousRange(IndxGrooming);
            
            if Ranges(1,3) == 0
                Ranges = [NaN NaN];
            else
                for RG = 1 : size(Ranges,1)-1
                    % Merge if just NaN between
                    if all(isnan(obj.Measurements.Data.Grooming(IndxGrooming(Ranges(RG,2))+1:IndxGrooming(Ranges(RG+1,1))-1)))
                        Ranges(RG+1,1) = Ranges(RG,1);
                        Ranges(RG,:) = NaN;
                    end
                end
                Ranges = Ranges(~isnan(Ranges(:,1)),:);
                Ranges = obj.Times(IndxGrooming(Ranges(:,[1 2])));

                
                % Merging if close
                if ~isempty(Ranges)
                    if size(Ranges,2)==1
                        Ranges = Ranges';
                    else
                        for RG = 1 : size(Ranges,1)-1
                            if (Ranges(RG+1,1) - Ranges(RG,2))<=obj.Parameters.Grooming.Merging
                                Ranges(RG+1,1) = Ranges(RG,1);
                                Ranges(RG,:) = NaN;
                            end
                        end
                        Ranges = Ranges(~isnan(Ranges(:,1)),:);
                    end
                    
                    % Minimum duration
                    Ranges(diff(Ranges,[],2)<obj.Parameters.Grooming.MinimumDuration,:) = [];
                    if isempty(Ranges)
                        Ranges = [NaN NaN];
                    elseif numel(Ranges)== 2 && size(Ranges,1) == 2
                        Ranges = Ranges';
                    end
                else
                    Ranges = [NaN NaN];
                end
                
            end
            if ~obj.Reprocessing
                obj.Detection.Data.Grooming = Ranges;
            end
            DT = find(contains(obj.Detection.ToPlot,'Grooming'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            %% Rearing / head dips
            % We dilate the area on the floor to get different "rings"
            % around
            % Then, if certain body parts are tracked in a specific ring,
            % this counts as rearing (to make it faster, coordinates are
            % rounded to directly check if they fall into a mask; the
            % alternative, the Matlab built-in inROI is slower and a bit of
            % an overkill here imo)
            
            %  disp('PxCmRatio')
            %  disp(obj.Parameters.PxCmRatio)
            if contains(obj.Basename,'EPM')
                for V = 1 : size(obj.ClosedArmVertices{1},1)
                    for W = 1 : size(obj.ClosedArmVertices{2},1)
                        DistanceVert(V,W) = Distance2D(obj.ClosedArmVertices{1}(V,:),obj.ClosedArmVertices{2}(W,:));
                    end
                end
                
                Mins = min(DistanceVert,[],2);
                [~,IndxMins1] = sort(Mins);
                [~,IndxMins11] = min(DistanceVert(IndxMins1(1),:));
                [~,IndxMins12] = min(DistanceVert(IndxMins1(2),:));
                CenterEPM = [obj.ClosedArmVertices{1}(IndxMins1(1),:);...
                    obj.ClosedArmVertices{2}(IndxMins11(1),:);...
                    obj.ClosedArmVertices{2}(IndxMins12(1),:);...
                    obj.ClosedArmVertices{1}(IndxMins1(2),:)];
                MaskCenterEPM = poly2mask(CenterEPM(:,1),CenterEPM(:,2),obj.Reader.Height,obj.Reader.Width);
                
                % We need an additional mask to handle the limits between
                % closed arms walls and the open arms extended mask
                DistanceClosedArm1_WallVertex1 = arrayfun(@(x) Distance2D(obj.ClosedArmVertices{1}(IndxMins1(1),:),obj.WallVerticesVertices(x,:)),1:4);
                [~,IndxMinx11] = min(DistanceClosedArm1_WallVertex1);
                obj.WallVerticesVertices(IndxMinx11,:) = obj.WallVerticesVertices(IndxMinx11,:) + 5* (obj.WallVerticesVertices(IndxMinx11,:)-obj.ClosedArmVertices{1}(IndxMins1(1),:));
                DistanceClosedArm1_WallVertex1 = obj.WallVerticesVertices(IndxMinx11,:);
                DistanceClosedArm1_WallVertex2 = arrayfun(@(x) Distance2D(obj.ClosedArmVertices{1}(IndxMins1(2),:),obj.WallVerticesVertices(x,:)),1:4);
                [~,IndxMinx12] = min(DistanceClosedArm1_WallVertex2);
                obj.WallVerticesVertices(IndxMinx12,:) = obj.WallVerticesVertices(IndxMinx12,:) + 5*(obj.WallVerticesVertices(IndxMinx12,:)-obj.ClosedArmVertices{1}(IndxMins1(2),:));
                DistanceClosedArm1_WallVertex2 = obj.WallVerticesVertices(IndxMinx12,:);
                MaskLimits_ClosedArm1 = [obj.ClosedArmVertices{1}(IndxMins1(1),:);DistanceClosedArm1_WallVertex1;DistanceClosedArm1_WallVertex2;obj.ClosedArmVertices{1}(IndxMins1(2),:)];
                MaskLimits_ClosedArm1_Mask = poly2mask(MaskLimits_ClosedArm1(:,1),MaskLimits_ClosedArm1(:,2),obj.Reader.Height,obj.Reader.Width);
                
                DistanceClosedArm2_WallVertex1 = arrayfun(@(x) Distance2D(obj.ClosedArmVertices{2}(IndxMins11(1),:),obj.WallVerticesVertices(x,:)),1:4);
                [~,IndxMinx21] = min(DistanceClosedArm2_WallVertex1);
                obj.WallVerticesVertices(IndxMinx21,:) = obj.WallVerticesVertices(IndxMinx21,:) + 5*(obj.WallVerticesVertices(IndxMinx21,:)-obj.ClosedArmVertices{2}(IndxMins11(1),:));
                DistanceClosedArm2_WallVertex1 = obj.WallVerticesVertices(IndxMinx21,:);
                DistanceClosedArm2_WallVertex2 = arrayfun(@(x) Distance2D(obj.ClosedArmVertices{2}(IndxMins12,:),obj.WallVerticesVertices(x,:)),1:4);
                [~,IndxMinx22] = min(DistanceClosedArm2_WallVertex2);
                obj.WallVerticesVertices(IndxMinx22,:) = obj.WallVerticesVertices(IndxMinx22,:) + 5*(obj.WallVerticesVertices(IndxMinx22,:)-obj.ClosedArmVertices{2}(IndxMins12,:));
                DistanceClosedArm2_WallVertex2 = obj.WallVerticesVertices(IndxMinx22,:);
                MaskLimits_ClosedArm2 = [obj.ClosedArmVertices{2}(IndxMins11(1),:);DistanceClosedArm2_WallVertex1;DistanceClosedArm2_WallVertex2;obj.ClosedArmVertices{2}(IndxMins12,:)];
                MaskLimits_ClosedArm2_Mask = poly2mask(MaskLimits_ClosedArm2(:,1),MaskLimits_ClosedArm2(:,2),obj.Reader.Height,obj.Reader.Width);
                
                AllVertices = [DistanceClosedArm1_WallVertex2;DistanceClosedArm2_WallVertex1;DistanceClosedArm2_WallVertex2];
                DistancesClosedArm1_WallVertex1 = arrayfun(@(x) Distance2D(DistanceClosedArm1_WallVertex1,AllVertices(x,:)),1:3);
                [~,IndxSort] = sort(DistancesClosedArm1_WallVertex1);
                VerticesPoly = [DistanceClosedArm1_WallVertex1;AllVertices(IndxSort(1),:);AllVertices(IndxSort(3),:);AllVertices(IndxSort(2),:)];
                MaskLimits_OpenArms_Mask = poly2mask(VerticesPoly(:,1),VerticesPoly(:,2),obj.Reader.Height,obj.Reader.Width)...
                    & ~MaskLimits_ClosedArm1_Mask & ~MaskLimits_ClosedArm2_Mask & ~MaskCenterEPM;
                MaskLimits_ClosedArms_Mask = (MaskLimits_ClosedArm1_Mask | MaskLimits_ClosedArm2_Mask) & ~MaskCenterEPM;
                
                
                ClosedArmsMask = poly2mask(obj.ClosedArmVertices{1}(:,1),obj.ClosedArmVertices{1}(:,2),obj.Reader.Height,obj.Reader.Width) |...
                    poly2mask(obj.ClosedArmVertices{2}(:,1),obj.ClosedArmVertices{2}(:,2),obj.Reader.Height,obj.Reader.Width);
                Mask_Max_ClosedArms = imdilate(ClosedArmsMask,strel('rect',round(obj.Parameters.PxCmRatio*obj.Parameters.Rearing.ThirdRing)*[1 1]));
                Mask_FirstExt_ClosedArms = imdilate(ClosedArmsMask,strel('rect',round(obj.Parameters.PxCmRatio*obj.Parameters.Rearing.FirstRing)*[1 1]));
                Mask_SecondExt_ClosedArms = imdilate(ClosedArmsMask,strel('rect',round(obj.Parameters.PxCmRatio*obj.Parameters.Rearing.SecondRing)*[1 1]));
                
                Mask_ZeroRing_ClosedArms = ~ClosedArmsMask & Mask_Max_ClosedArms & ~MaskLimits_OpenArms_Mask & ~MaskCenterEPM;
                Mask_FirstRing_ClosedArms = ~Mask_FirstExt_ClosedArms & Mask_Max_ClosedArms & ~MaskLimits_OpenArms_Mask & ~MaskCenterEPM;
                Mask_SecondRing_ClosedArms = ~Mask_SecondExt_ClosedArms & Mask_Max_ClosedArms & ~MaskLimits_OpenArms_Mask & ~MaskCenterEPM;
                               
                Contours_ZeroRing_ClosedArms = contourc(double(Mask_ZeroRing_ClosedArms),1);
                Contours_ZeroRing_ClosedArms(:,Contours_ZeroRing_ClosedArms(1,:)<=1 | Contours_ZeroRing_ClosedArms(2,:)<=1 | Contours_ZeroRing_ClosedArms(1,:)>obj.Reader.Width | Contours_ZeroRing_ClosedArms(2,:)>obj.Reader.Height) = NaN;
                Contours_FirstRing_ClosedArms = contourc(double(Mask_FirstRing_ClosedArms),1);
                Contours_FirstRing_ClosedArms(:,Contours_FirstRing_ClosedArms(1,:)<=1 | Contours_FirstRing_ClosedArms(2,:)<=1 | Contours_FirstRing_ClosedArms(1,:)>obj.Reader.Width | Contours_FirstRing_ClosedArms(2,:)>obj.Reader.Height) = NaN;
                Contours_SecondRing_ClosedArms = contourc(double(Mask_SecondRing_ClosedArms),1);
                Contours_SecondRing_ClosedArms(:,Contours_SecondRing_ClosedArms(1,:)<=1 | Contours_SecondRing_ClosedArms(2,:)<=1 | Contours_SecondRing_ClosedArms(1,:)>obj.Reader.Width | Contours_SecondRing_ClosedArms(2,:)>obj.Reader.Height) = NaN;
                Contours_MaxRing_ClosedArms = contourc(double(Mask_Max_ClosedArms),1);
                Contours_MaxRing_ClosedArms(:,Contours_MaxRing_ClosedArms(1,:)<=1 | Contours_MaxRing_ClosedArms(2,:)<=1 | Contours_MaxRing_ClosedArms(1,:)>obj.Reader.Width | Contours_MaxRing_ClosedArms(2,:)>obj.Reader.Height) = NaN;
                
                obj.Parameters.Rearing.Contours_ZeroRing = Contours_ZeroRing_ClosedArms;
                obj.Parameters.Rearing.Contours_FirstRing = Contours_FirstRing_ClosedArms;
                obj.Parameters.Rearing.Contours_SecondRing = Contours_SecondRing_ClosedArms;
                obj.Parameters.Rearing.Contours_MaxRing = Contours_MaxRing_ClosedArms;
                obj.Parameters.Rearing.Mask_ZeroRing = Mask_ZeroRing_ClosedArms;
                obj.Parameters.Rearing.Mask_FirstRing = Mask_FirstRing_ClosedArms;
                obj.Parameters.Rearing.Mask_SecondRing = Mask_SecondRing_ClosedArms;
                obj.Parameters.Rearing.Mask_Max = Mask_Max_ClosedArms;

                OpenArmsMask = obj.MaskLimits & ~Mask_ZeroRing_ClosedArms & ~ClosedArmsMask & ~MaskCenterEPM;
                if isfield(obj.Parameters.HeadDips,'ErosionIn')
                    OpenArmsMask_Eroded = imerode(OpenArmsMask,strel('rect',round(obj.Parameters.PxCmRatio*obj.Parameters.HeadDips.ErosionIn)*[1 1]));
                else
                    OpenArmsMask_Eroded = OpenArmsMask;
                end
                
                Mask_Max_OpenArms = imdilate(OpenArmsMask,strel('rect',round(obj.Parameters.PxCmRatio*obj.Parameters.HeadDips.ThirdRing)*[1 1]));
                Mask_FirstExt_OpenArms = imdilate(OpenArmsMask,strel('rect',round(obj.Parameters.PxCmRatio*obj.Parameters.HeadDips.FirstRing)*[1 1]));
                Mask_SecondExt_OpenArms = imdilate(OpenArmsMask,strel('rect',round(obj.Parameters.PxCmRatio*obj.Parameters.HeadDips.SecondRing)*[1 1]));
                
                %  Mask_ZeroRing_OpenArms = ~OpenArmsMask & Mask_Max_OpenArms & ~MaskLimits_ClosedArms_Mask & ~MaskCenterEPM;
                Mask_ZeroRing_OpenArms = ~OpenArmsMask_Eroded & Mask_Max_OpenArms & ~MaskLimits_ClosedArms_Mask & ~MaskCenterEPM;
                
                Mask_FirstRing_OpenArms = ~Mask_FirstExt_OpenArms & Mask_Max_OpenArms & ~MaskLimits_ClosedArms_Mask & ~MaskCenterEPM;
                
                Mask_SecondRing_OpenArms = ~Mask_SecondExt_OpenArms & Mask_Max_OpenArms & ~MaskLimits_ClosedArms_Mask & ~MaskCenterEPM;
                
                Contours_ZeroRing_OpenArms = contourc(double(Mask_ZeroRing_OpenArms),1);
                Contours_ZeroRing_OpenArms(:,Contours_ZeroRing_OpenArms(1,:)<=1 | Contours_ZeroRing_OpenArms(2,:)<=1 | Contours_ZeroRing_OpenArms(1,:)>obj.Reader.Width | Contours_ZeroRing_OpenArms(2,:)>obj.Reader.Height) = NaN;
                Contours_FirstRing_OpenArms = contourc(double(Mask_FirstRing_OpenArms),1);
                Contours_FirstRing_OpenArms(:,Contours_FirstRing_OpenArms(1,:)<=1 | Contours_FirstRing_OpenArms(2,:)<=1 | Contours_FirstRing_OpenArms(1,:)>obj.Reader.Width | Contours_FirstRing_OpenArms(2,:)>obj.Reader.Height) = NaN;
                Contours_SecondRing_OpenArms = contourc(double(Mask_SecondRing_OpenArms),1);
                Contours_SecondRing_OpenArms(:,Contours_SecondRing_OpenArms(1,:)<=1 | Contours_SecondRing_OpenArms(2,:)<=1 | Contours_SecondRing_OpenArms(1,:)>obj.Reader.Width | Contours_SecondRing_OpenArms(2,:)>obj.Reader.Height) = NaN;
                Contours_MaxRing_OpenArms = contourc(double(Mask_Max_OpenArms),1);
                Contours_MaxRing_OpenArms(:,Contours_MaxRing_OpenArms(1,:)<=1 | Contours_MaxRing_OpenArms(2,:)<=1 | Contours_MaxRing_OpenArms(1,:)>obj.Reader.Width | Contours_MaxRing_OpenArms(2,:)>obj.Reader.Height) = NaN;
                
                obj.Parameters.HeadDips.Contours_ZeroRing = Contours_ZeroRing_OpenArms;
                obj.Parameters.HeadDips.Contours_FirstRing = Contours_FirstRing_OpenArms;
                obj.Parameters.HeadDips.Contours_SecondRing = Contours_SecondRing_OpenArms;
                obj.Parameters.HeadDips.Contours_MaxRing = Contours_MaxRing_OpenArms;
                obj.Parameters.HeadDips.Mask_ZeroRing = Mask_ZeroRing_OpenArms;
                obj.Parameters.HeadDips.Mask_FirstRing = Mask_FirstRing_OpenArms;
                obj.Parameters.HeadDips.Mask_SecondRing = Mask_SecondRing_OpenArms;
                obj.Parameters.HeadDips.Mask_Max = Mask_Max_OpenArms;
                
                
                % Then, if certain body parts are tracked in a specific ring,
                % this counts as rearing (to make it faster, coordinates are
                % rounded to directly check if they fall into a mask; the
                % alternative, the Matlab built-in inROI is slower and a bit of
                % an overkill here imo)
                Rearing = false(size(obj.Coordinates.TailBase,1),1);
                for TB = 1 : size(obj.Coordinates.TailBase,1)
                    if ~isnan(obj.Coordinates.Snout(TB,2))
                        if Mask_SecondRing_ClosedArms(round(obj.Coordinates.Snout(TB,2)),round(obj.Coordinates.Snout(TB,1)))
                            Rearing(TB) = true;
                        end
                    end
                    if ~isnan(obj.Coordinates.EarLeft(TB,2)) && ~isnan(obj.Coordinates.EarRight(TB,2))
                        if Mask_FirstRing_ClosedArms(round(obj.Coordinates.EarLeft(TB,2)),round(obj.Coordinates.EarLeft(TB,1))) && Mask_FirstRing_ClosedArms(round(obj.Coordinates.EarRight(TB,2)),round(obj.Coordinates.EarRight(TB,1)))
                            Rearing(TB) = true;
                        end
                    end
                    if ~isnan(obj.Coordinates.ForePawRight(TB,2))
                        if Mask_FirstRing_ClosedArms(round(obj.Coordinates.ForePawRight(TB,2)),round(obj.Coordinates.ForePawRight(TB,1)))
                            Rearing(TB) = true;
                        end
                    end
                    if ~isnan(obj.Coordinates.ForePawLeft(TB,2))
                        if Mask_FirstRing_ClosedArms(round(obj.Coordinates.ForePawLeft(TB,2)),round(obj.Coordinates.ForePawLeft(TB,1))) 
                            Rearing(TB) = true;
                        end
                    end
                end
                Rearing(obj.Detection.Logical.Grooming) = false;

                HeadDips = false(size(obj.Coordinates.TailBase,1),1);
                for TB = 1 : size(obj.Coordinates.TailBase,1)
                    if ~isnan(obj.Coordinates.Snout(TB,2))
                        if Mask_FirstRing_OpenArms(round(obj.Coordinates.Snout(TB,2)),round(obj.Coordinates.Snout(TB,1)))
                            HeadDips(TB) = true;
                        end
                    end
                    if ~isnan(obj.Coordinates.EarLeft(TB,2)) && ~isnan(obj.Coordinates.EarRight(TB,2))
                        if (Mask_ZeroRing_OpenArms(round(obj.Coordinates.EarLeft(TB,2)),round(obj.Coordinates.EarLeft(TB,1))) || Mask_FirstRing_OpenArms(round(obj.Coordinates.EarLeft(TB,2)),round(obj.Coordinates.EarLeft(TB,1)))) && ...
                                (Mask_ZeroRing_OpenArms(round(obj.Coordinates.EarRight(TB,2)),round(obj.Coordinates.EarRight(TB,1))) || Mask_FirstRing_OpenArms(round(obj.Coordinates.EarRight(TB,2)),round(obj.Coordinates.EarRight(TB,1))))
                            HeadDips(TB) = true;
                        end
                    end
                end
                HeadDips(obj.Detection.Logical.Grooming) = false;
                
                

                
            else
                if strcmpi(obj.MaskShape,'circle')
                    ShapeStrel = 'disk';
                    SyStrel = 1;
                else
                    ShapeStrel = 'rect';
                    SyStrel = [1 1];
                end
                
                Mask_Max = imdilate(obj.MaskLimits,strel(ShapeStrel,round(obj.Parameters.PxCmRatio*obj.Parameters.Rearing.ThirdRing)*SyStrel));
                Mask_FirstExt = imdilate(obj.MaskLimits,strel(ShapeStrel,round(obj.Parameters.PxCmRatio*obj.Parameters.Rearing.FirstRing)*SyStrel));
                Mask_SecondExt = imdilate(obj.MaskLimits,strel(ShapeStrel,round(obj.Parameters.PxCmRatio*obj.Parameters.Rearing.SecondRing)*SyStrel));
                
                Mask_ZeroRing = ~obj.MaskLimits & Mask_Max;
                Mask_FirstRing = ~Mask_FirstExt & Mask_Max;
                Mask_SecondRing = ~Mask_SecondExt;
                
                Contours_ZeroRing = contourc(double(Mask_ZeroRing),1);
                Contours_ZeroRing(:,Contours_ZeroRing(1,:)<=1 | Contours_ZeroRing(2,:)<=1 | Contours_ZeroRing(1,:)>obj.Reader.Width | Contours_ZeroRing(2,:)>obj.Reader.Height) = NaN;
                Contours_FirstRing = contourc(double(Mask_FirstRing),1);
                Contours_FirstRing(:,Contours_FirstRing(1,:)<=1 | Contours_FirstRing(2,:)<=1 | Contours_FirstRing(1,:)>obj.Reader.Width | Contours_FirstRing(2,:)>obj.Reader.Height) = NaN;
                Contours_SecondRing = contourc(double(Mask_SecondRing),1);
                Contours_SecondRing(:,Contours_SecondRing(1,:)<=1 | Contours_SecondRing(2,:)<=1 | Contours_SecondRing(1,:)>obj.Reader.Width | Contours_SecondRing(2,:)>obj.Reader.Height) = NaN;
                Contours_MaxRing = contourc(double(Mask_Max),1);
                Contours_MaxRing(:,Contours_MaxRing(1,:)<=1 | Contours_MaxRing(2,:)<=1 | Contours_MaxRing(1,:)>obj.Reader.Width | Contours_MaxRing(2,:)>obj.Reader.Height) = NaN;
                
                obj.Parameters.Rearing.Contours_ZeroRing = Contours_ZeroRing;
                obj.Parameters.Rearing.Contours_FirstRing = Contours_FirstRing;
                obj.Parameters.Rearing.Contours_SecondRing = Contours_SecondRing;
                obj.Parameters.Rearing.Contours_MaxRing = Contours_MaxRing;
                obj.Parameters.Rearing.Mask_ZeroRing = Mask_ZeroRing;
                obj.Parameters.Rearing.Mask_FirstRing = Mask_FirstRing;
                obj.Parameters.Rearing.Mask_SecondRing = Mask_SecondRing;
                obj.Parameters.Rearing.Mask_Max = Mask_Max;
                
                Rearing = false(size(obj.Coordinates.TailBase,1),1);
                for TB = 1 : size(obj.Coordinates.TailBase,1)
                    if ~isnan(obj.Coordinates.Snout(TB,2))
                        if Mask_SecondRing(round(obj.Coordinates.Snout(TB,2)),round(obj.Coordinates.Snout(TB,1)))
                            Rearing(TB) = true;
                        end
                    end
                    if ~isnan(obj.Coordinates.EarLeft(TB,2)) && ~isnan(obj.Coordinates.EarRight(TB,2))
                        if Mask_FirstRing(round(obj.Coordinates.EarLeft(TB,2)),round(obj.Coordinates.EarLeft(TB,1))) && Mask_FirstRing(round(obj.Coordinates.EarRight(TB,2)),round(obj.Coordinates.EarRight(TB,1)))
                            Rearing(TB) = true;
                        end
                    end
                    if ~isnan(obj.Coordinates.ForePawRight(TB,2))
                        if Mask_FirstRing(round(obj.Coordinates.ForePawRight(TB,2)),round(obj.Coordinates.ForePawRight(TB,1)))
                            Rearing(TB) = true;
                        end
                    end
                    if ~isnan(obj.Coordinates.ForePawLeft(TB,2))
                        if Mask_FirstRing(round(obj.Coordinates.ForePawLeft(TB,2)),round(obj.Coordinates.ForePawLeft(TB,1)))
                            Rearing(TB) = true;
                        end
                    end
                end
                Rearing(obj.Detection.Logical.Grooming) = false;
                if contains(obj.Basename,'LDB')
                    
                    MaskLimits = poly2mask(obj.WallVertices{1}(:,1),obj.WallVertices{1}(:,2),obj.Reader.Height,obj.Reader.Width);
                    Mask_FirstExt = imerode(MaskLimits,strel(ShapeStrel,round(obj.Parameters.PxCmRatio*obj.Parameters.WallRearing.FirstRing)*SyStrel));
                    Mask_SecondExt = imerode(MaskLimits,strel(ShapeStrel,round(obj.Parameters.PxCmRatio*obj.Parameters.WallRearing.SecondRing)*SyStrel));
                    
                    Mask_ZeroRing = Mask_SecondExt;
                    Mask_FirstRing = Mask_FirstExt;
                    Mask_SecondRing = Mask_SecondExt;
                    
%                     Contours_ZeroRing = contourc(double(Mask_ZeroRing),1);
%                     Contours_ZeroRing(:,Contours_ZeroRing(1,:)<=1 | Contours_ZeroRing(2,:)<=1 | Contours_ZeroRing(1,:)>obj.Reader.Width | Contours_ZeroRing(2,:)>obj.Reader.Height) = NaN;
%                     Contours_FirstRing = contourc(double(Mask_FirstRing),1);
%                     Contours_FirstRing(:,Contours_FirstRing(1,:)<=1 | Contours_FirstRing(2,:)<=1 | Contours_FirstRing(1,:)>obj.Reader.Width | Contours_FirstRing(2,:)>obj.Reader.Height) = NaN;
%                     Contours_SecondRing = contourc(double(Mask_SecondRing),1);
%                     Contours_SecondRing(:,Contours_SecondRing(1,:)<=1 | Contours_SecondRing(2,:)<=1 | Contours_SecondRing(1,:)>obj.Reader.Width | Contours_SecondRing(2,:)>obj.Reader.Height) = NaN;
%                     Contours_MaxRing = contourc(double(Mask_Max),1);
%                     Contours_MaxRing(:,Contours_MaxRing(1,:)<=1 | Contours_MaxRing(2,:)<=1 | Contours_MaxRing(1,:)>obj.Reader.Width | Contours_MaxRing(2,:)>obj.Reader.Height) = NaN;
                    
                    WallRearing = false(size(obj.Coordinates.TailBase,1),1);
                    for TB = 1 : size(obj.Coordinates.TailBase,1)
                        if ~isnan(obj.Coordinates.Snout(TB,2))
                            if Mask_SecondRing(round(obj.Coordinates.Snout(TB,2)),round(obj.Coordinates.Snout(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                        if ~isnan(obj.Coordinates.EarLeft(TB,2)) && ~isnan(obj.Coordinates.EarRight(TB,2))
                            if Mask_FirstRing(round(obj.Coordinates.EarLeft(TB,2)),round(obj.Coordinates.EarLeft(TB,1))) && Mask_FirstRing(round(obj.Coordinates.EarRight(TB,2)),round(obj.Coordinates.EarRight(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                        if ~isnan(obj.Coordinates.ForePawRight(TB,2))
                            if Mask_FirstRing(round(obj.Coordinates.ForePawRight(TB,2)),round(obj.Coordinates.ForePawRight(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                        if ~isnan(obj.Coordinates.ForePawLeft(TB,2))
                            if Mask_FirstRing(round(obj.Coordinates.ForePawLeft(TB,2)),round(obj.Coordinates.ForePawLeft(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                    end
                    
                    
                    MaskLimits = poly2mask(obj.WallVertices{2}(:,1),obj.WallVertices{2}(:,2),obj.Reader.Height,obj.Reader.Width);
                    Mask_FirstExt = imerode(MaskLimits,strel(ShapeStrel,round(obj.Parameters.PxCmRatio*obj.Parameters.WallRearing.FirstRing)*SyStrel));
                    Mask_SecondExt = imerode(MaskLimits,strel(ShapeStrel,round(obj.Parameters.PxCmRatio*obj.Parameters.WallRearing.SecondRing)*SyStrel));
                    
                    Mask_ZeroRing = Mask_SecondExt;
                    Mask_FirstRing = Mask_FirstExt;
                    Mask_SecondRing = Mask_SecondExt;
                  
                    
%                     Contours_ZeroRing = contourc(double(Mask_ZeroRing),1);
%                     Contours_ZeroRing(:,Contours_ZeroRing(1,:)<=1 | Contours_ZeroRing(2,:)<=1 | Contours_ZeroRing(1,:)>obj.Reader.Width | Contours_ZeroRing(2,:)>obj.Reader.Height) = NaN;
%                     Contours_FirstRing = contourc(double(Mask_FirstRing),1);
%                     Contours_FirstRing(:,Contours_FirstRing(1,:)<=1 | Contours_FirstRing(2,:)<=1 | Contours_FirstRing(1,:)>obj.Reader.Width | Contours_FirstRing(2,:)>obj.Reader.Height) = NaN;
%                     Contours_SecondRing = contourc(double(Mask_SecondRing),1);
%                     Contours_SecondRing(:,Contours_SecondRing(1,:)<=1 | Contours_SecondRing(2,:)<=1 | Contours_SecondRing(1,:)>obj.Reader.Width | Contours_SecondRing(2,:)>obj.Reader.Height) = NaN;
%                     Contours_MaxRing = contourc(double(Mask_Max),1);
%                     Contours_MaxRing(:,Contours_MaxRing(1,:)<=1 | Contours_MaxRing(2,:)<=1 | Contours_MaxRing(1,:)>obj.Reader.Width | Contours_MaxRing(2,:)>obj.Reader.Height) = NaN;
                    
                    WallRearing = false(size(obj.Coordinates.TailBase,1),1);
                    for TB = 1 : size(obj.Coordinates.TailBase,1)
                        if ~isnan(obj.Coordinates.Snout(TB,2))
                            if Mask_SecondRing(round(obj.Coordinates.Snout(TB,2)),round(obj.Coordinates.Snout(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                        if ~isnan(obj.Coordinates.EarLeft(TB,2)) && ~isnan(obj.Coordinates.EarRight(TB,2))
                            if Mask_FirstRing(round(obj.Coordinates.EarLeft(TB,2)),round(obj.Coordinates.EarLeft(TB,1))) && Mask_FirstRing(round(obj.Coordinates.EarRight(TB,2)),round(obj.Coordinates.EarRight(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                        if ~isnan(obj.Coordinates.ForePawRight(TB,2))
                            if Mask_FirstRing(round(obj.Coordinates.ForePawRight(TB,2)),round(obj.Coordinates.ForePawRight(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                        if ~isnan(obj.Coordinates.ForePawLeft(TB,2))
                            if Mask_FirstRing(round(obj.Coordinates.ForePawLeft(TB,2)),round(obj.Coordinates.ForePawLeft(TB,1)))
                                WallRearing(TB) = true;
                            end
                        end
                    end
                    WallRearing(obj.Detection.Logical.Grooming) = false;
%                 else
%                     WallRearing = false(size(obj.Coordinates.TailBase,1),1);
                end
            end
            if ~isfield(obj.Detection.Logical,'OpenRearing')
                obj.Detection.Logical.OpenRearing = BaseArray;
                obj.Detection.Data.OpenRearing = [];
            else
                DT = find(contains(obj.Detection.ToPlot,'Rearing') & ~contains(obj.Detection.ToPlot,'Open')) & ~contains(obj.Detection.ToPlot,'Wall');
                obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                    for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                        Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                        obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                    end
                end
                obj.Detection.ToPlot = [obj.Detection.ToPlot,'OpenRearing'];
            end
            if ~obj.Reprocessing
                Rearing(obj.Detection.Logical.OpenRearing) = false;
                obj.Detection.Data.Rearing = obj.GetRanges(Rearing,obj.Parameters.Rearing.Merging,obj.Parameters.Rearing.MinimumDuration);
                DT = find(contains(obj.Detection.ToPlot,'Rearing') & ~contains(obj.Detection.ToPlot,'Open') & ~contains(obj.Detection.ToPlot,'Wall'));
                obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                    for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                        Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                        obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                    end
                end
                if contains(obj.Basename,'LDB')
                    WallRearing(obj.Detection.Logical.OpenRearing) = false;
                    WallRearing(obj.Detection.Logical.Rearing) = false;
                    obj.Detection.Data.WallRearing = obj.GetRanges(WallRearing,obj.Parameters.Rearing.Merging,obj.Parameters.Rearing.MinimumDuration);
                    obj.Detection.ToPlot = [obj.Detection.ToPlot,'WallRearing'];
                    DT = find(contains(obj.Detection.ToPlot,'WallRearing'));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                    if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                        for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                            Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                            obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                        end
                    end
                else
                    obj.Detection.Logical.WallRearing = BaseArray;
                    obj.Detection.Data.WallRearing = [];
                end
                
                if contains(obj.Basename,'EPM')
                    HeadDips(obj.Detection.Logical.Rearing) = false;
                    HeadDips(obj.Detection.Logical.OpenRearing) = false;
                    obj.Detection.Data.HeadDips = obj.GetRanges(HeadDips,obj.Parameters.HeadDips.Merging,obj.Parameters.HeadDips.MinimumDuration);
                    obj.Detection.ToPlot = [obj.Detection.ToPlot,'HeadDips'];
                end

                obj.Detection.Data.Struggle = [NaN NaN];
            elseif obj.MissingWallRearing
                if contains(obj.Basename,'LDB')
                    DT = find(strcmpi(obj.Detection.ToPlot,'Rearing'));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                    if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                        for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                            Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                            obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                        end
                    end
                  
                    WallRearing(obj.Detection.Logical.OpenRearing) = false;
                    WallRearing(obj.Detection.Logical.Rearing) = false;
                                       
                    
                    obj.Detection.Data.WallRearing = obj.GetRanges(WallRearing,obj.Parameters.Rearing.Merging,obj.Parameters.Rearing.MinimumDuration);
                    obj.Detection.ToPlot = [obj.Detection.ToPlot,'WallRearing'];
                    DT = find(contains(obj.Detection.ToPlot,'WallRearing'));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                    if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                        for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                            Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                            obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                        end
                    end
                else
                    obj.Detection.Logical.WallRearing = BaseArray;
                    obj.Detection.Data.WallRearing = [];
                end
            end
            
            
            DT = find(contains(obj.Detection.ToPlot,'Rearing') & ~contains(obj.Detection.ToPlot,'Open') & ~contains(obj.Detection.ToPlot,'Wall'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            DT = find(contains(obj.Detection.ToPlot,'WallRearing'));
            if any(DT)
                obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                    for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                        Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                        obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                    end
                end
            else
                obj.Detection.Logical.WallRearing = BaseArray;
                obj.Detection.Data.WallRearing = [];
            end
            if ~any(contains(obj.Detection.ToPlot,'HeadDips'))
                obj.Detection.Data.HeadDips = [];
                obj.Detection.Logical.HeadDips = BaseArray;
            else
                DT = find(contains(obj.Detection.ToPlot,'HeadDips'));
                obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                    for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                        Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                        obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                    end
                end
            end
            
            %% Stretch-attend
            SAT =  obj.Parameters.StretchAttend.BothHindPaws;
            SATHigh = obj.Parameters.StretchAttend.SingleHindPaw;
            
            
            StretchAttend = (...
                TotalLength>obj.Parameters.StretchAttend.Length * obj.Parameters.SizeCorrection) & smoothdata(obj.Measurements.Data.StepSpeed,'gaussian',5)<obj.Parameters.StretchAttend.StepSpeed &...
                ((obj.Measurements.Data.HindPawRight<SAT & obj.Measurements.Data.HindPawLeft<SAT) | (obj.Measurements.Data.HindPawLeft<SAT & (obj.Score.HindPawRight<0.9 | obj.Score.HindPawRight<SATHigh)) | (obj.Measurements.Data.HindPawRight<SAT &...
                (obj.Score.HindPawLeft<0.9 | obj.Measurements.Data.HindPawLeft<SATHigh)) &...
                ~obj.Detection.Logical.HeadDips & ~obj.Detection.Logical.Grooming) ;
            if ~obj.Reprocessing
                if obj.Parameters.Rearing.RearingOverSAP
                    StretchAttend(obj.Detection.Logical.Rearing) = false;
                    StretchAttend(obj.Detection.Logical.WallRearing) = false;
                    StretchAttend(obj.Detection.Logical.OpenRearing) = false;
                end
                obj.Detection.Data.StretchAttend = obj.GetRanges(StretchAttend,obj.Parameters.StretchAttend.Merging,obj.Parameters.StretchAttend.MinimumDuration);
            end
            DT = find(contains(obj.Detection.ToPlot,'StretchAttend'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            if 0
            %% Head rotation
            UpperBodyRotation = NaN(size(obj.Coordinates.TailBase,1),1);
            LowerBodyRotation = NaN(size(obj.Coordinates.TailBase,1),1);
            StepHeadScan = 10;
            parfor TB = StepHeadScan+1 : size(obj.Coordinates.TailBase,1)
                if ~isnan(MidEars_Points(TB,1)) && ~isnan(MidEars_Points(TB-StepHeadScan,1))
                    Vector1 = ([MidEars_Points(TB-StepHeadScan,:) - CenterG(TB-StepHeadScan,:)  0])/norm([MidEars_Points(TB-StepHeadScan,:) - CenterG(TB-StepHeadScan,:) 0]);
                    Vector2 = ([MidEars_Points(TB,:) - CenterG(TB,:)  0])/norm([MidEars_Points(TB,:) - CenterG(TB,:)  0]);
                    x = cross(Vector1,Vector2);
                    c = sign(dot(x,[0 0 1])) * norm(x);
                    UpperBodyRotation(TB) = rad2deg(atan2(c,dot(Vector1,Vector2)));
                end
                if (Score.TailBase(TB) > 0.9 && Score.TailBase(TB-StepHeadScan) > 0.9)
                    Vector1 = ([CenterG(TB-StepHeadScan,:) - Coordinates.TailBase(TB-StepHeadScan,:)   0])/norm([CenterG(TB-StepHeadScan,:)- Coordinates.TailBase(TB-StepHeadScan,:) 0]);
                    Vector2 = ([CenterG(TB,:) - Coordinates.TailBase(TB,:) 0])/norm([CenterG(TB,:) - Coordinates.TailBase(TB,:)  0]);
                    x = cross(Vector1,Vector2);
                    c = sign(dot(x,[0 0 1])) * norm(x);
                    LowerBodyRotation(TB) = rad2deg(atan2(c,dot(Vector1,Vector2)));
                end
            end
            obj.Measurements.Data.HeadScan = smoothdata(abs(UpperBodyRotation),'gaussian',20)-smoothdata(abs(LowerBodyRotation),'gaussian',20);
            end
            
            
            %% Area explored
            AreaExplored = NaN(size(obj.Coordinates.TailBase,1),1);
            BoundingBox = cell(size(obj.Coordinates.TailBase,1),1);
            CenterGBB = CenterG';
            CenterGBB = smoothdata(CenterGBB ,2,'movmedian',5);
            StepArea = (round(obj.Reader.FrameRate) * 3);
            StepAreaS = ceil(StepArea*0.75);
            StepAreaE = ceil(StepArea*0.25);
            for AE = StepAreaS+1 : size(obj.Coordinates.TailBase,1)-StepAreaE
                Points = CenterGBB (:,AE-StepAreaS:AE+StepAreaE);
                Points = Points(:,~isnan(Points(1,:)));
                if ~isempty(Points) && size(Points,2)>3
                    try % Lazy fix for occasional not enough and collinear points (very rare)
                        BB = (minBoundingBox(Points))';
                        AreaExplored(AE) = max([Distance2D(BB(1,:),BB(2,:)) Distance2D(BB(2,:),BB(3,:))]) * Distance2D(BB(1,:),BB(2,:)) * Distance2D(BB(2,:),BB(3,:)) /(obj.Parameters.PxCmRatio^3);
                        BoundingBox{AE} = BB;
                    catch
                        BoundingBox{AE} = NaN(4,2);
                        warning(['Error computing the convex hull for frame ' num2str(AE) '. The points may be collinear.'])
                    end
                else
                    BoundingBox{AE} = NaN(4,2);
                end
            end
            obj.Measurements.Data.BoundingBox = BoundingBox;
            obj.Measurements.Data.AreaExplored = AreaExplored;
            
            %% Freezing
%             for DT = find(contains(obj.Detection.ToPlot,'Grooming') | contains(obj.Detection.ToPlot,'StretchAttend') | contains(obj.Detection.ToPlot,'HeadDips') | contains(obj.Detection.ToPlot,'Rearing') | contains(obj.Detection.ToPlot,'OpenRearing'))
%                 obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
%                 if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
%                     for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
%                         Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
%                         obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
%                     end
%                end
%             end
%             if ~isfield(obj.Detection.Logical,'HeadDips') 
%                 obj.Detection.Logical.HeadDips = BaseArray;
%             end
%             if ~isfield(obj.Detection.Logical,'OpenRearing')
%                 obj.Detection.Logical.OpenRearing = BaseArray;
%             end
            SmoothMo = smoothdata(obj.Measurements.Data.Motion,10);
            FindIndex = find(SmoothMo<1 & ~obj.Detection.Logical.Grooming &...
            ~obj.Detection.Logical.StretchAttend & ~obj.Detection.Logical.HeadDips &...
            ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.WallRearing & ~obj.Detection.Logical.TailRattling); % not reapplied after merging because of min duration vs merging criterion
            FreezingEpisodes = FindContinuousRange(FindIndex);
            FreezingEpisodes = FindIndex(FreezingEpisodes(:,[1 2]));
            FreezingEpisodes = obj.Times(FreezingEpisodes);
            
            % Merging
            for KFS = 2 : numel(FreezingEpisodes(:,1))
                if (FreezingEpisodes(KFS,1)-FreezingEpisodes(KFS-1,2))<0.150
                    FreezingEpisodes(KFS,1) = FreezingEpisodes(KFS-1,1);
                    FreezingEpisodes(KFS-1,:) = NaN(1,2);
                end
            end
            FreezingEpisodes = FreezingEpisodes(~isnan(FreezingEpisodes(:,1)),:);
            
            FreezingEpisodesLength = (FreezingEpisodes(:,2)-FreezingEpisodes(:,1));
            FreezingEpisodes(FreezingEpisodesLength<=0.5,:) = [];
           
            if ~obj.Reprocessing
            obj.Detection.Data.Freezing = FreezingEpisodes;
            end
            DT = find(contains(obj.Detection.ToPlot,'Freezing'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            
            %% Not travelling / no freezing
            % No motion criterion because we should assume that if it is 
            % not freezing, the motion can be actually in a very low range,
            % and it makes more sense to attribute the range to areabound
            % than to the "remaining" (rather explo)
            
            % Paradigm
            if contains(obj.Basename, 'OF')
                ParadigmKey = 'OF';
            elseif contains(obj.Basename, 'CD')
                ParadigmKey = 'CD';
            elseif contains(obj.Basename, 'EPM')
                ParadigmKey = 'EPM';
            elseif contains(obj.Basename, 'Ext')
                ParadigmKey = 'Ext';
            elseif contains(obj.Basename, 'PreExp')
                ParadigmKey = 'PreExp';
            elseif contains(obj.Basename, 'LDB')
                ParadigmKey = 'LDB';
            elseif contains(obj.Basename, 'Opto')
                ParadigmKey = 'Opto';
            else
                ParadigmKey = 'Ext';
                warning(['No paradigm key; using arbitrary value. CHECK IT!'])
            end
            
            FindIndex = find(AreaExplored<obj.DefaultParameters.Motion.AreaBound.(ParadigmKey) & ~obj.Detection.Logical.Freezing &... 
                ~obj.Detection.Logical.Grooming & ~obj.Detection.Logical.StretchAttend &...
                ~obj.Detection.Logical.HeadDips & ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.WallRearing &...
                ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.TailRattling);
            AreaBoundEpisodes = FindContinuousRange(FindIndex);
            AreaBoundEpisodes = FindIndex(AreaBoundEpisodes(:,[1 2]));
            AreaBoundEpisodes = obj.Times(AreaBoundEpisodes);
            
            % Merging
            for KFS = 2 : numel(AreaBoundEpisodes(:,1))
                if (AreaBoundEpisodes(KFS,1)-AreaBoundEpisodes(KFS-1,2))<0.15
                    AreaBoundEpisodes(KFS,1) = AreaBoundEpisodes(KFS-1,1);
                    AreaBoundEpisodes(KFS-1,:) = NaN(1,2);
                end
            end
            AreaBoundEpisodes = AreaBoundEpisodes(~isnan(AreaBoundEpisodes(:,1)),:);
            
            AreaBoundEpisodesLength = (AreaBoundEpisodes(:,2)-AreaBoundEpisodes(:,1));
%             AreaBoundEpisodes(AreaBoundEpisodesLength<=0.1,:) = [];

            if ~obj.Reprocessing
            obj.Detection.Data.AreaBound = AreaBoundEpisodes;
            end
            DT = find(contains(obj.Detection.ToPlot,'AreaBound'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            %% Flight
            FindIndex = find(obj.Measurements.Data.StepSpeed>=20 &...
                ~obj.Detection.Logical.Freezing & ~obj.Detection.Logical.Grooming & ...
                ~obj.Detection.Logical.StretchAttend & ~obj.Detection.Logical.HeadDips &...
                ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.WallRearing &...
                ~obj.Detection.Logical.AreaBound);
            if ~isempty(FindIndex)
            FlightEpisodes = FindContinuousRange(FindIndex);
            FlightEpisodes = FindIndex(FlightEpisodes(:,[1 2]));
            FlightEpisodes = obj.Times(FlightEpisodes);
            if size(FlightEpisodes,2) == 1
                FlightEpisodes = FlightEpisodes';
            end
            % Merging
            for KFS = 2 : numel(FlightEpisodes(:,1))
                if (FlightEpisodes(KFS,1)-FlightEpisodes(KFS-1,2))<0.15
                    FlightEpisodes(KFS,1) = FlightEpisodes(KFS-1,1);
                    FlightEpisodes(KFS-1,:) = NaN(1,2);
                end
            end
            FlightEpisodes = FlightEpisodes(~isnan(FlightEpisodes(:,1)),:);
            
            FlightEpisodesLength = (FlightEpisodes(:,2)-FlightEpisodes(:,1));
            FlightEpisodes(FlightEpisodesLength<=0.2,:) = [];
            else
                FlightEpisodes = [];
            end
            
            if ~obj.Reprocessing
            obj.Detection.Data.Flight = FlightEpisodes;
            end
            DT = find(contains(obj.Detection.ToPlot,'Flight'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            %% The rest: moving for exploration
            FindIndex = find(~obj.Detection.Logical.Freezing &...
                ~obj.Detection.Logical.Grooming & ~obj.Detection.Logical.StretchAttend &...
                ~obj.Detection.Logical.HeadDips & ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.WallRearing &...
                ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.AreaBound &...
                ~obj.Detection.Logical.Flight & ~obj.Detection.Logical.TailRattling);
            RemainingEpisodes = FindContinuousRange(FindIndex);
            RemainingEpisodes = FindIndex(RemainingEpisodes(:,[1 2]));
            RemainingEpisodes = obj.Times(RemainingEpisodes);
            
            if ~obj.Reprocessing
            obj.Detection.Data.Remaining = RemainingEpisodes;
            end
            DT = find(contains(obj.Detection.ToPlot,'Remaining'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            % Apply merging/deletion:
            % The idea is to never merge freezing episodes, but to get rid
            % of very brief events of "remaining"/bound in area
            
            % Two passes: one to merge small episodes only to large
            % episodes, the second to merge very small episodes to adjacent
            % episodes even if they are a bit small
            
            SmallThresholds = [0.25 0.1];
            MergingThresholds = [0.5 Inf];
            
            if ~obj.Reprocessing
                for LoopM = 1:2
                    % First, when episodes on both side
                    SmallRemaining = find(diff(obj.Detection.Data.Remaining,[],2)<=SmallThresholds(LoopM));
                    AreaBoundD = diff(obj.Detection.Data.AreaBound,[],2);
                    for SR = 1 : numel(SmallRemaining)
                        if ~(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times(1) || obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times(end))
                            % Times from the ranges are derived from real frames times:
                            % we don't have to worry about rounding and getting the
                            % right frames
                            IndxBefore = obj.Detection.Data.AreaBound(:,2)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times,1,'first')-1);
                            IndexAfter = obj.Detection.Data.AreaBound(:,1)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times,1,'first')+1);
                            if any(IndxBefore) && any(IndexAfter)
                                if AreaBoundD(IndxBefore)>=MergingThresholds(LoopM) && AreaBoundD(IndexAfter)>=MergingThresholds(LoopM)
                                    obj.Detection.Data.Remaining(SmallRemaining(SR),:) = NaN;
                                    obj.Detection.Data.AreaBound(IndexAfter,1) = obj.Detection.Data.AreaBound(IndxBefore,1);
                                    obj.Detection.Data.AreaBound(IndxBefore,:) = NaN;
                                end
                            end
                        end
                    end
                    obj.Detection.Data.Remaining(isnan(obj.Detection.Data.Remaining(:,1)),:) = [];
                    obj.Detection.Data.AreaBound(isnan(obj.Detection.Data.AreaBound(:,1)),:) = [];
                    
                    SmallAreaBound = find(diff(obj.Detection.Data.AreaBound,[],2)<=SmallThresholds(LoopM));
                    RemainingD = diff(obj.Detection.Data.Remaining,[],2);
                    for SR = 1 : numel(SmallAreaBound)
                        if ~(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times(1) || obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times(end))
                            % Times from the ranges are derived from real frames times:
                            % we don't have to worry about rounding and getting the
                            % right frames
                            IndxBefore = obj.Detection.Data.Remaining(:,2)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times,1,'first')-1);
                            IndexAfter = obj.Detection.Data.Remaining(:,1)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times,1,'first')+1);
                            if any(IndxBefore) && any(IndexAfter)
                                if RemainingD(IndxBefore)>=MergingThresholds(LoopM) && RemainingD(IndexAfter)>=MergingThresholds(LoopM)
                                    obj.Detection.Data.AreaBound(SmallAreaBound(SR),:) = NaN;
                                    obj.Detection.Data.Remaining(IndexAfter,1) = obj.Detection.Data.Remaining(IndxBefore,1);
                                    obj.Detection.Data.Remaining(IndxBefore,:) = NaN;
                                end
                            end
                        end
                    end
                    obj.Detection.Data.AreaBound(isnan(obj.Detection.Data.AreaBound(:,1)),:) = [];
                    obj.Detection.Data.Remaining(isnan(obj.Detection.Data.Remaining(:,1)),:) = [];
                    
                    % Same thing, but with small episodes that are not in the
                    % middle of the other behaviour we can replace them with: we
                    % can still merge if there is one side now; it is risky because
                    % we might
                    
                    SmallRemaining = find(diff(obj.Detection.Data.Remaining,[],2)<=SmallThresholds(LoopM));
                    AreaBoundD = diff(obj.Detection.Data.AreaBound,[],2);
                    for SR = 1 : numel(SmallRemaining)
                        if ~(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times(1) || obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times(end))
                            % Times from the ranges are derived from real frames times:
                            % we don't have to worry about rounding and getting the
                            % right frames
                            IndxBefore = obj.Detection.Data.AreaBound(:,2)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times,1,'first')-1);
                            IndexAfter = obj.Detection.Data.AreaBound(:,1)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times,1,'first')+1);
                            if any(IndxBefore)
                                if AreaBoundD(IndxBefore)>=MergingThresholds(LoopM)
                                    obj.Detection.Data.AreaBound(IndxBefore,2) = obj.Detection.Data.Remaining(SmallRemaining(SR),2);
                                    obj.Detection.Data.Remaining(SmallRemaining(SR),:) = NaN;
                                end
                            elseif any(IndexAfter)
                                if AreaBoundD(IndexAfter)>=MergingThresholds(LoopM)
                                    obj.Detection.Data.AreaBound(IndexAfter,1) = obj.Detection.Data.Remaining(SmallRemaining(SR),1);
                                    obj.Detection.Data.Remaining(SmallRemaining(SR),:) = NaN;
                                end
                            end
                        end
                    end
                    obj.Detection.Data.Remaining(isnan(obj.Detection.Data.Remaining(:,1)),:) = [];
                    
                    SmallAreaBound = find(diff(obj.Detection.Data.AreaBound,[],2)<=SmallThresholds(LoopM));
                    RemainingD = diff(obj.Detection.Data.Remaining,[],2);
                    for SR = 1 : numel(SmallAreaBound)
                        if ~(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times(1) || obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times(end))
                            % Times from the ranges are derived from real frames times:
                            % we don't have to worry about rounding and getting the
                            % right frames
                            IndxBefore = obj.Detection.Data.Remaining(:,2)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times,1,'first')-1);
                            IndexAfter = obj.Detection.Data.Remaining(:,1)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times,1,'first')+1);
                            if any(IndxBefore)
                                if RemainingD(IndxBefore)>=MergingThresholds(LoopM)
                                    obj.Detection.Data.Remaining(IndxBefore,2) = obj.Detection.Data.AreaBound(SmallAreaBound(SR),2);
                                    obj.Detection.Data.AreaBound(SmallAreaBound(SR),:) = NaN;
                                end
                            elseif any(IndexAfter)
                                if RemainingD(IndexAfter)>=MergingThresholds(LoopM)
                                    obj.Detection.Data.Remaining(IndexAfter,1) = obj.Detection.Data.AreaBound(SmallAreaBound(SR),1);
                                    obj.Detection.Data.AreaBound(SmallAreaBound(SR),:) = NaN;
                                end
                            end
                        end
                    end
                    obj.Detection.Data.AreaBound(isnan(obj.Detection.Data.AreaBound(:,1)),:) = [];
                    
                end
            end
            
            % Prepare logical arrays
            for DT = 1 : numel(obj.Detection.ToPlot)
                if ~isfield(obj.Detection.Logical,obj.Detection.ToPlot{DT})
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                    if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                        for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                            Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                            obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                        end
                    end
                end
            end
            
            if 0
                %% Prepare sound (even if disabled by default since it can be switched back on)
                if ~(numel(unique(obj.Detection.ToPlot)) == numel(unique(obj.DetectionSound)) && numel(unique(obj.DetectionSound)) == numel(unique(obj.SoundPriority))) || (numel(obj.DetectionSound) ~= numel(unique(obj.DetectionSound))) || (numel(obj.SoundPriority) ~= numel(unique(obj.SoundPriority)))
                    warning('Sound parameters number of elements are not matching. No sound will be generated.')
                    obj.SoundMode = false;
                else
                    BaseDuration = (0:1/obj.SoundFrequency:100)'; % 100s should be enough for even the largest of behavioural bout -if not we'll have to change this :)
                    DurationAll = (0:1/obj.SoundFrequency:obj.Times(end))';
                    SoundAll = zeros(size(BaseDuration));
                    for DT = numel(obj.SoundPriority) : -1 : 1
                        CurrDetected = find(strcmpi(obj.Detection.ToPlot, obj.SoundPriority{DT}));
                        if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{CurrDetected}))
                            SoundBase = sin(2*pi*obj.DetectionSound(CurrDetected)*BaseDuration);
                            for Ev = 1 : size(obj.Detection.Data.(obj.Detection.ToPlot{CurrDetected}),1)
                                IndxEv = FindInInterval(DurationAll,obj.Detection.Data.(obj.Detection.ToPlot{CurrDetected})(Ev,:));
                                SoundAll(IndxEv(1):IndxEv(2)) = SoundBase(1:diff(IndxEv)+1);
                            end
                        end
                    end
                    obj.SoundTimes = DurationAll;
                    obj.Sound = SoundAll;
                end
            end
            
            %% Update measurements plots
            if isfield(obj.Handles,'MeasurementsAxes')
                delete(obj.Handles.MeasurementsAxes(:))
                if isfield(obj.Handles,'MeasurementsAxes')
                    obj.Handles = rmfield(obj.Handles,'MeasurementsAxes');
                end
                if isfield(obj.Handles,'MeasurementsPlots_TimeLine')
                    obj.Handles = rmfield(obj.Handles,'MeasurementsPlots_TimeLine');
                end
            end
            if ~isempty(obj.Measurements.ToPlot)
                for F = numel(obj.Measurements.ToPlot) : -1 : 1
                    obj.Handles.MeasurementsAxes(F) = axes('Units','normalized','Position',[0.55 0.95-F*(0.85/numel(obj.Measurements.ToPlot)) 0.425 0.85/numel(obj.Measurements.ToPlot)-0.01],'Color','w'); hold on
                    hold on
                    obj.Handles.MeasurementsPlots(F) = plot(obj.Times,obj.Measurements.Data.(obj.Measurements.ToPlot{F}),'LineWidth',1,'Parent',obj.Handles.MeasurementsAxes(F));
                    YLimF = obj.Handles.MeasurementsAxes(F).YLim;
                    switch lower(obj.Measurements.ToPlot{F})
                        case 'totallength'
                            obj.Handles.StretchAttend_LengthThreshold = plot(obj.Times([1 end]),obj.Parameters.StretchAttend.Length * obj.Parameters.SizeCorrection*[1;1],'k','LineWidth',1.5,'Parent',obj.Handles.MeasurementsAxes(F),...
                                'ButtonDownFcn',{@(~,~)obj.StretchAttend_LengthThresholdCB});
                        case 'grooming'
                            obj.Handles.Grooming_Threshold = plot(obj.Times([1 end]),obj.Parameters.Grooming.Threshold*[1;1],'k','LineWidth',1.5,'Parent',obj.Handles.MeasurementsAxes(F),...
                                'ButtonDownFcn',{@(~,~)obj.Grooming_ThresholdCB});
                        case 'tailmotion'
                            obj.Handles.TailRattling_TailMotionThreshold = plot(obj.Times([1 end]),obj.Parameters.TailRattling.Threshold*[1;1],'k','LineWidth',1.5,'Parent',obj.Handles.MeasurementsAxes(F),...
                                'ButtonDownFcn',{@(~,~)obj.TailRattling_TailMotionThresholdCB});
                    end
                    obj.Handles.MeasurementsPlots_TimeLine(F) = plot(obj.CurrentTime*[1;1],YLimF,'k','LineWidth',3,'Parent',obj.Handles.MeasurementsAxes(F),...
                        'ButtonDownFcn',{@(src,evt)obj.SliderCB(src,evt)});
                    obj.Handles.MeasurementsAxes(F).YLim = YLimF;
                end
                if numel(obj.Measurements.ToPlot)>1
                    for F = 1 : numel(obj.Measurements.ToPlot)-1
                        obj.Handles.MeasurementsAxes(F).XAxis.Visible = 'off';
                    end
                end
                
                for F = 1 : numel(obj.Measurements.ToPlot)
                    obj.Handles.MeasurementsAxes(F).LineWidth = 3;
                    obj.Handles.MeasurementsAxes(F).FontSize = 13;
                    obj.Handles.MeasurementsAxes(F).FontWeight = 'b';
                    obj.Handles.MeasurementsAxes(F).TickDir = 'out';
                    obj.Handles.MeasurementsAxes(F).YLabel.String = obj.Measurements.ToPlot{F};
                end
%                 PosLabel = arrayfun(@(x) obj.Handles.MeasurementsAxes(x).YLabel.Position(1),1:numel(obj.Measurements.ToPlot));
%                 for F = 1 : numel(obj.Measurements.ToPlot)
%                     obj.Handles.MeasurementsAxes(F).YLabel.Position(1) = min(PosLabel);
%                 end
                obj.Handles.MeasurementsAxes(end).XLabel.String = 'Time (s)';
            end
            linkaxes(obj.Handles.MeasurementsAxes(:),'x')
            drawnow
            
            DC = DefColors;
            DC = repmat(DC,10,1);
            % Update detection plots
            if isfield(obj.Handles,'DetectionAxes')
                delete(obj.Handles.DetectionAxes(:))
                obj.Handles = rmfield(obj.Handles,'DetectionAxes');
            end
            if ~isempty(obj.Detection.ToPlot)
               
                for F = numel(obj.Detection.ToPlot) : -1 : 1
                    obj.Handles.DetectionAxes(F) = axes('Units','normalized','Position',[0.08 0.285-F*(0.2/numel(obj.Detection.ToPlot)) 0.42 0.2/numel(obj.Detection.ToPlot)],'Color','w','Tag',num2str(F)); hold on
                    obj.Handles.DetectionAxes(F).ButtonDownFcn = {@(src,evt)obj.SelectAxes(src,evt)};
                    hold on
                    if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{F}))
                        obj.Handles.DetectionRanges.(obj.Detection.ToPlot{F}) = arrayfun(@(x) fill(obj.Detection.Data.(obj.Detection.ToPlot{F})(x,[1 2 2 1]),[0 0 1 1],DC(F,:),'EdgeColor',DC(F,:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(F),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag',obj.Detection.ToPlot{F},'UserData',num2str(x)),1:size(obj.Detection.Data.(obj.Detection.ToPlot{F}),1));
                    else
                        obj.Handles.DetectionRanges.(obj.Detection.ToPlot{F}) = [];
                    end
                    obj.Handles.DetectionPlots_TimeLine(F) = plot(obj.CurrentTime*[1;1],[-0.25 1.25],'k','LineWidth',3,'Parent',obj.Handles.DetectionAxes(F),...
                        'ButtonDownFcn',{@(src,evt)obj.SliderCB(src,evt)});
                end
                if numel(obj.Detection.ToPlot)>1
                    for F = 1 : numel(obj.Detection.ToPlot)-1
                        obj.Handles.DetectionAxes(F).XAxis.Visible = 'off';
                    end
                end
                for F = 1 : numel(obj.Detection.ToPlot)
                    obj.Handles.DetectionAxes(F).LineWidth = 3;
                    obj.Handles.DetectionAxes(F).FontSize = 13;
                    obj.Handles.DetectionAxes(F).FontWeight = 'b';
                    obj.Handles.DetectionAxes(F).TickDir = 'out';
                    obj.Handles.DetectionAxes(F).YLabel.String = obj.Detection.ToPlot{F};
                    obj.Handles.DetectionAxes(F).YTick = [];
                    obj.Handles.DetectionAxes(F).YLabel.Rotation = 0;
                    obj.Handles.DetectionAxes(F).YLabel.Color = 'k';
                    obj.Handles.DetectionAxes(F).YLabel.HorizontalAlignment = 'right';
                    obj.Handles.DetectionAxes(F).YLabel.VerticalAlignment = 'middle';
                    obj.Handles.DetectionAxes(F).YLim = [-0.25 1.25];
                    ZoomHandleSubF = zoom(obj.Handles.DetectionAxes(F));
                    ZoomHandleSubF.Motion = 'horizontal';
                    ZoomHandleSubF.ActionPostCallback = @(~,~)obj.EvaluateWindow;
                    obj.Handles.DetectionAxes(F).Toolbar.Visible = 'off';
                end
                obj.Handles.DetectionAxes(1).Toolbar.Visible = 'on';
                obj.Handles.DetectionAxes(numel(obj.Detection.ToPlot)).XLabel.String = 'Time (s)';
                for AxL = 1 : numel(obj.Handles.MeasurementsAxes)
                    ZoomHandleSub = zoom(obj.Handles.MeasurementsAxes(AxL));
                    ZoomHandleSub.ActionPostCallback = @(~,~)obj.EvaluateWindow;
                    ZoomHandleSubF.Motion = 'both';
                end
                linkaxes([obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes],'x')
            end
%             obj.CurrentTime = 10;
            obj.Playing = false;
            obj.PlayMovies('Initialize');
            hold(obj.Handles.Player.Axes,'on')
            obj.Handles.Rearing.Contours_ZeroRing = plot(obj.Parameters.Rearing.Contours_ZeroRing(1,:),obj.Parameters.Rearing.Contours_ZeroRing(2,:),'Parent',obj.Handles.Player.Axes,'Color',obj.PlotParameters.RearingLimitsColor.ZeroRing,'LineWidth',1);
            obj.Handles.Rearing.Contours_FirstRing = plot(obj.Parameters.Rearing.Contours_FirstRing(1,:),obj.Parameters.Rearing.Contours_FirstRing(2,:),'Parent',obj.Handles.Player.Axes,'Color',obj.PlotParameters.RearingLimitsColor.FirstRing,'LineWidth',1);
            obj.Handles.Rearing.Contours_SecondRing = plot(obj.Parameters.Rearing.Contours_SecondRing(1,:),obj.Parameters.Rearing.Contours_SecondRing(2,:),'Parent',obj.Handles.Player.Axes,'Color',obj.PlotParameters.RearingLimitsColor.SecondRing,'LineWidth',1);
            pause(0.01);
            obj.Handles.AreaExploredK = plot(NaN(1,5),NaN(1,5),'Color','k','LineWidth',3,'Parent',obj.Handles.Player.Axes);
            obj.Handles.AreaExploredW = plot(NaN(1,5),NaN(1,5),'Color','w','LineWidth',1.5,'Parent',obj.Handles.Player.Axes);
            
            if contains(obj.Basename,'EPM')
                obj.Handles.HeadDips.Contours_ZeroRing = plot(obj.Parameters.HeadDips.Contours_ZeroRing(1,:),obj.Parameters.HeadDips.Contours_ZeroRing(2,:),'Parent',obj.Handles.Player.Axes,'Color',obj.PlotParameters.HeadDipsLimitsColor.ZeroRing,'LineWidth',1);
                obj.Handles.HeadDips.Contours_FirstRing = plot(obj.Parameters.HeadDips.Contours_FirstRing(1,:),obj.Parameters.HeadDips.Contours_FirstRing(2,:),'Parent',obj.Handles.Player.Axes,'Color',obj.PlotParameters.HeadDipsLimitsColor.FirstRing,'LineWidth',1);
                obj.Handles.HeadDips.Contours_SecondRing = plot(obj.Parameters.HeadDips.Contours_SecondRing(1,:),obj.Parameters.HeadDips.Contours_SecondRing(2,:),'Parent',obj.Handles.Player.Axes,'Color',obj.PlotParameters.HeadDipsLimitsColor.SecondRing,'LineWidth',1);
            end
            if ~obj.Enabled.Limits
                obj.Handles.Rearing.Contours_ZeroRing.Color = 'none';
                obj.Handles.Rearing.Contours_FirstRing.Color = 'none';
                obj.Handles.Rearing.Contours_SecondRing.Color = 'none';
                if contains(obj.Basename,'EPM')
                    obj.Handles.HeadDips.Contours_ZeroRing.Color = 'none';
                    obj.Handles.HeadDips.Contours_FirstRing.Color = 'none';
                    obj.Handles.HeadDips.Contours_SecondRing .Color = 'none';
                end
            end
            if ~obj.Enabled.AreaBound
                obj.Handles.AreaExploredK.Color = 'none';
                obj.Handles.AreaExploredW.Color = 'none';
            end
            
            Subs = [obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes];
            for S = 1 : numel(Subs)
                obj.Handles.LineStartRemovedWindows{S} = [];
                obj.Handles.LineEndRemovedWindows{S} = [];
                if isempty(obj.ExclusionRanges)
                    obj.Handles.FillRemovedWindows{S} = [];
                else
                    obj.Handles.FillRemovedWindows{S} = arrayfun(@(x) fill([obj.ExclusionRanges(x,1) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,1)], [Subs(S).YLim(1) * [1 1]  Subs(S).YLim(2) * [1 1]],[0.85 0.9 0.85],'FaceAlpha',0.5,'EdgeColor','none','Parent',Subs(S),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.ExclusionRanges(:,1)));
                    uistack(obj.Handles.FillRemovedWindows{S},'bottom')
                end
            end
            obj.SelectedDetection = [];
            obj.Handles.InsertRange_Button.Enable = 'off';
            obj.Handles.InsertRange_Button.Visible = 'off';
            
            % Overlay axes
            if isfield(obj.Handles,'OverlayAxes')
                delete(obj.Handles.OverlayAxes)
            end
            obj.Handles.OverlayAxes = axes('Position',obj.Handles.Player.Axes.Position,'Color','none'); hold on
            hold(obj.Handles.OverlayAxes,'on')
            
            obj.Handles.OverlayAxes.XAxis.Visible = 'off';
            obj.Handles.OverlayAxes.YAxis.Visible = 'off';
            obj.Handles.OverlayAxes.XLim = [0 100];
            axis(obj.Handles.OverlayAxes,'equal');drawnow
            obj.Handles.OverlayAxes.XLimMode = 'manual';
            obj.Handles.OverlayAxes.YLimMode = 'manual';
            obj.Handles.OverlayAxes.Interactions = [];
            YL = obj.Handles.OverlayAxes.YLim;
            axis(obj.Handles.OverlayAxes,'normal')
            obj.Handles.OverlayAxes.YLim = [0 round(diff(YL))];
            YL = obj.Handles.OverlayAxes.YLim;
            
            t = linspace(0,2*pi);
            % Make patch
            if isfield(obj.Handles,'OverlayDetection')
                obj.Handles = rmfield(obj.Handles,'OverlayDetection');
            end
            
            obj.PlotParameters.OverlayBandWidth = YL(2)/2.2 / numel(obj.Detection.ToPlot);
            for DT = 1 : numel(obj.Detection.ToPlot)
                Radius_Out = YL(2)/2 - (DT-1)*obj.PlotParameters.OverlayBandWidth;
                Radius_In = Radius_Out-obj.PlotParameters.OverlayBandWidth;
                xin = 50 + Radius_In*cos(t);
                xout = 50 + Radius_Out*cos(t);
                yin = YL(2)/2 + Radius_In*sin(t);
                yout = YL(2)/2 + Radius_Out*sin(t);
                obj.Handles.OverlayDetection(DT) = fill([xout,xin],[yout,yin],DC(DT,:),'linestyle','none','facealpha',obj.PlotParameters.OverlayFaceAplha,'Visible','off','Parent',obj.Handles.OverlayAxes);
            end
            
            obj.PlayMovies;
        end
        
        function Ranges = GetRanges(obj,Logical,Merging,MinimumDuration)
            IndexT = find(Logical);
            if ~isempty(IndexT)
                Ranges = FindContinuousRange(IndexT);
                Ranges = obj.Times(IndexT(Ranges(:,[1 2])));
                if numel(Ranges)== 2
                    Ranges = Ranges';
                end
            else
                Ranges = [];
            end
            
            % Merging if close
            if ~isempty(Ranges)
                if size(Ranges,2)==1
                    Ranges = Ranges';
                else
                    for RG = 1 : size(Ranges,1)-1
                        if (Ranges(RG+1,1) - Ranges(RG,2))<=Merging
                            Ranges(RG+1,1) = Ranges(RG,1);
                            Ranges(RG,:) = NaN;
                        end
                    end
                    Ranges = Ranges(~isnan(Ranges(:,1)),:);
                end
                
                % Minimum duration
                Ranges(diff(Ranges,[],2)<MinimumDuration,:) = [];
                if numel(Ranges)== 2 && size(Ranges,1) == 2
                    Ranges = Ranges';
                end
            end
        end
        
        function ReRunAlgorithm(obj)
            % After adjusting thresholds,we want to rerun the algorithm
            SmoothMo = smoothdata(obj.Measurements.Data.Motion,10);
            FindIndex = find(SmoothMo<1 & ~obj.Detection.Logical.Grooming &...
            ~obj.Detection.Logical.StretchAttend & ~obj.Detection.Logical.HeadDips &...
            ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.WallRearing & ~obj.Detection.Logical.TailRattling); % not reapplied after merging because of min duration vs merging criterion
            FreezingEpisodes = FindContinuousRange(FindIndex);
            FreezingEpisodes = FindIndex(FreezingEpisodes(:,[1 2]));
            FreezingEpisodes = obj.Times(FreezingEpisodes);
            
            % Merging
            for KFS = 2 : numel(FreezingEpisodes(:,1))
                if (FreezingEpisodes(KFS,1)-FreezingEpisodes(KFS-1,2))<0.150
                    FreezingEpisodes(KFS,1) = FreezingEpisodes(KFS-1,1);
                    FreezingEpisodes(KFS-1,:) = NaN(1,2);
                end
            end
            FreezingEpisodes = FreezingEpisodes(~isnan(FreezingEpisodes(:,1)),:);
            
            FreezingEpisodesLength = (FreezingEpisodes(:,2)-FreezingEpisodes(:,1));
            FreezingEpisodes(FreezingEpisodesLength<=0.5,:) = [];
           
            obj.Detection.Data.Freezing = FreezingEpisodes;
            
            BaseArray = false(size(obj.Times));
            DT = find(contains(obj.Detection.ToPlot,'Freezing'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            
            %% Not travelling / no freezing
            % No motion criterion because we should assume that if it is 
            % not freezing, the motion can be actually in a very low range,
            % and it makes more sense to attribute the range to areabound
            % than to the "remaining" (rather explo)
            
            % Paradigm
            if contains(obj.Basename, 'OF')
                ParadigmKey = 'OF';
            elseif contains(obj.Basename, 'CD')
                ParadigmKey = 'CD';
            elseif contains(obj.Basename, 'EPM')
                ParadigmKey = 'EPM';
            elseif contains(obj.Basename, 'Ext')
                ParadigmKey = 'Ext';
            elseif contains(obj.Basename, 'PreExp')
                ParadigmKey = 'PreExp';
            elseif contains(obj.Basename, 'LDB')
                ParadigmKey = 'LDB';
            elseif contains(obj.Basename, 'Opto')
                ParadigmKey = 'Opto';
            else
                ParadigmKey = 'Ext';
                warning(['No paradigm key; using arbitrary value. CHECK IT!'])
            end
            
            FindIndex = find(obj.Measurements.Data.AreaExplored<obj.DefaultParameters.Motion.AreaBound.(ParadigmKey) & ~obj.Detection.Logical.Freezing &... 
                ~obj.Detection.Logical.Grooming & ~obj.Detection.Logical.StretchAttend &...
                ~obj.Detection.Logical.HeadDips & ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.WallRearing &...
                ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.TailRattling);
            AreaBoundEpisodes = FindContinuousRange(FindIndex);
            AreaBoundEpisodes = FindIndex(AreaBoundEpisodes(:,[1 2]));
            AreaBoundEpisodes = obj.Times(AreaBoundEpisodes);
            
            % Merging
            for KFS = 2 : numel(AreaBoundEpisodes(:,1))
                if (AreaBoundEpisodes(KFS,1)-AreaBoundEpisodes(KFS-1,2))<0.15
                    AreaBoundEpisodes(KFS,1) = AreaBoundEpisodes(KFS-1,1);
                    AreaBoundEpisodes(KFS-1,:) = NaN(1,2);
                end
            end
            AreaBoundEpisodes = AreaBoundEpisodes(~isnan(AreaBoundEpisodes(:,1)),:);
            
            AreaBoundEpisodesLength = (AreaBoundEpisodes(:,2)-AreaBoundEpisodes(:,1));
%             AreaBoundEpisodes(AreaBoundEpisodesLength<=0.1,:) = [];
            obj.Detection.Data.AreaBound = AreaBoundEpisodes;
            
            DT = find(contains(obj.Detection.ToPlot,'AreaBound'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            %% Flight
            FindIndex = find(obj.Measurements.Data.StepSpeed>=20 &...
                ~obj.Detection.Logical.Freezing & ~obj.Detection.Logical.Grooming & ...
                ~obj.Detection.Logical.StretchAttend & ~obj.Detection.Logical.HeadDips &...
                ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.WallRearing &...
                ~obj.Detection.Logical.AreaBound);
            if ~isempty(FindIndex)
            FlightEpisodes = FindContinuousRange(FindIndex);
            FlightEpisodes = FindIndex(FlightEpisodes(:,[1 2]));
            FlightEpisodes = obj.Times(FlightEpisodes);
            if size(FlightEpisodes,2) == 1
                FlightEpisodes = FlightEpisodes';
            end
            % Merging
            for KFS = 2 : numel(FlightEpisodes(:,1))
                if (FlightEpisodes(KFS,1)-FlightEpisodes(KFS-1,2))<0.15
                    FlightEpisodes(KFS,1) = FlightEpisodes(KFS-1,1);
                    FlightEpisodes(KFS-1,:) = NaN(1,2);
                end
            end
            FlightEpisodes = FlightEpisodes(~isnan(FlightEpisodes(:,1)),:);
            
            FlightEpisodesLength = (FlightEpisodes(:,2)-FlightEpisodes(:,1));
            FlightEpisodes(FlightEpisodesLength<=0.2,:) = [];
            else
                FlightEpisodes = [];
            end
            obj.Detection.Data.Flight = FlightEpisodes;
            
            DT = find(contains(obj.Detection.ToPlot,'Flight'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            %% The rest: moving for exploration
            FindIndex = find(~obj.Detection.Logical.Freezing &...
                ~obj.Detection.Logical.Grooming & ~obj.Detection.Logical.StretchAttend &...
                ~obj.Detection.Logical.HeadDips & ~obj.Detection.Logical.Rearing & ~obj.Detection.Logical.WallRearing &...
                ~obj.Detection.Logical.OpenRearing & ~obj.Detection.Logical.AreaBound &...
                ~obj.Detection.Logical.Flight & ~obj.Detection.Logical.TailRattling);
            RemainingEpisodes = FindContinuousRange(FindIndex);
            RemainingEpisodes = FindIndex(RemainingEpisodes(:,[1 2]));
            RemainingEpisodes = obj.Times(RemainingEpisodes);
            obj.Detection.Data.Remaining = RemainingEpisodes;

            DT = find(contains(obj.Detection.ToPlot,'Remaining'));
            obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
            if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                    Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                    obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                end
            end
            
            % Apply merging/deletion:
            % The idea is to never merge freezing episodes, but to get rid
            % of very brief events of "remaining"/bound in area
            
            % Two passes: one to merge small episodes only to large
            % episodes, the second to merge very small episodes to adjacent
            % episodes even if they are a bit small
            
            SmallThresholds = [0.25 0.1];
            MergingThresholds = [0.5 Inf];
            
            for LoopM = 1:2
                % First, when episodes on both side
                SmallRemaining = find(diff(obj.Detection.Data.Remaining,[],2)<=SmallThresholds(LoopM));
                AreaBoundD = diff(obj.Detection.Data.AreaBound,[],2);
                for SR = 1 : numel(SmallRemaining)
                    if ~(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times(1) || obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times(end))
                        % Times from the ranges are derived from real frames times:
                        % we don't have to worry about rounding and getting the
                        % right frames
                        IndxBefore = obj.Detection.Data.AreaBound(:,2)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times,1,'first')-1);
                        IndexAfter = obj.Detection.Data.AreaBound(:,1)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times,1,'first')+1);
                        if any(IndxBefore) && any(IndexAfter)
                            if AreaBoundD(IndxBefore)>=MergingThresholds(LoopM) && AreaBoundD(IndexAfter)>=MergingThresholds(LoopM)
                                obj.Detection.Data.Remaining(SmallRemaining(SR),:) = NaN;
                                obj.Detection.Data.AreaBound(IndexAfter,1) = obj.Detection.Data.AreaBound(IndxBefore,1);
                                obj.Detection.Data.AreaBound(IndxBefore,:) = NaN;
                            end
                        end
                    end
                end
                obj.Detection.Data.Remaining(isnan(obj.Detection.Data.Remaining(:,1)),:) = [];
                obj.Detection.Data.AreaBound(isnan(obj.Detection.Data.AreaBound(:,1)),:) = [];
                
                SmallAreaBound = find(diff(obj.Detection.Data.AreaBound,[],2)<=SmallThresholds(LoopM));
                RemainingD = diff(obj.Detection.Data.Remaining,[],2);
                for SR = 1 : numel(SmallAreaBound)
                    if ~(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times(1) || obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times(end))
                        % Times from the ranges are derived from real frames times:
                        % we don't have to worry about rounding and getting the
                        % right frames
                        IndxBefore = obj.Detection.Data.Remaining(:,2)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times,1,'first')-1);
                        IndexAfter = obj.Detection.Data.Remaining(:,1)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times,1,'first')+1);
                        if any(IndxBefore) && any(IndexAfter)
                            if RemainingD(IndxBefore)>=MergingThresholds(LoopM) && RemainingD(IndexAfter)>=MergingThresholds(LoopM)
                                obj.Detection.Data.AreaBound(SmallAreaBound(SR),:) = NaN;
                                obj.Detection.Data.Remaining(IndexAfter,1) = obj.Detection.Data.Remaining(IndxBefore,1);
                                obj.Detection.Data.Remaining(IndxBefore,:) = NaN;
                            end
                        end
                    end
                end
                obj.Detection.Data.AreaBound(isnan(obj.Detection.Data.AreaBound(:,1)),:) = [];
                obj.Detection.Data.Remaining(isnan(obj.Detection.Data.Remaining(:,1)),:) = [];
                
                % Same thing, but with small episodes that are not in the
                % middle of the other behaviour we can replace them with: we
                % can still merge if there is one side now; it is risky because
                % we might
                
                SmallRemaining = find(diff(obj.Detection.Data.Remaining,[],2)<=SmallThresholds(LoopM));
                AreaBoundD = diff(obj.Detection.Data.AreaBound,[],2);
                for SR = 1 : numel(SmallRemaining)
                    if ~(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times(1) || obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times(end))
                        % Times from the ranges are derived from real frames times:
                        % we don't have to worry about rounding and getting the
                        % right frames
                        IndxBefore = obj.Detection.Data.AreaBound(:,2)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),1) == obj.Times,1,'first')-1);
                        IndexAfter = obj.Detection.Data.AreaBound(:,1)== obj.Times(find(obj.Detection.Data.Remaining(SmallRemaining(SR),2) == obj.Times,1,'first')+1);
                        if any(IndxBefore)
                            if AreaBoundD(IndxBefore)>=MergingThresholds(LoopM)
                                obj.Detection.Data.AreaBound(IndxBefore,2) = obj.Detection.Data.Remaining(SmallRemaining(SR),2);
                                obj.Detection.Data.Remaining(SmallRemaining(SR),:) = NaN;
                            end
                        elseif any(IndexAfter)
                            if AreaBoundD(IndexAfter)>=MergingThresholds(LoopM)
                                obj.Detection.Data.AreaBound(IndexAfter,1) = obj.Detection.Data.Remaining(SmallRemaining(SR),1);
                                obj.Detection.Data.Remaining(SmallRemaining(SR),:) = NaN;
                            end
                        end
                    end
                end
                obj.Detection.Data.Remaining(isnan(obj.Detection.Data.Remaining(:,1)),:) = [];
                
                SmallAreaBound = find(diff(obj.Detection.Data.AreaBound,[],2)<=SmallThresholds(LoopM));
                RemainingD = diff(obj.Detection.Data.Remaining,[],2);
                for SR = 1 : numel(SmallAreaBound)
                    if ~(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times(1) || obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times(end))
                        % Times from the ranges are derived from real frames times:
                        % we don't have to worry about rounding and getting the
                        % right frames
                        IndxBefore = obj.Detection.Data.Remaining(:,2)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),1) == obj.Times,1,'first')-1);
                        IndexAfter = obj.Detection.Data.Remaining(:,1)== obj.Times(find(obj.Detection.Data.AreaBound(SmallAreaBound(SR),2) == obj.Times,1,'first')+1);
                        if any(IndxBefore)
                            if RemainingD(IndxBefore)>=MergingThresholds(LoopM)
                                obj.Detection.Data.Remaining(IndxBefore,2) = obj.Detection.Data.AreaBound(SmallAreaBound(SR),2);
                                obj.Detection.Data.AreaBound(SmallAreaBound(SR),:) = NaN;
                            end
                        elseif any(IndexAfter)
                            if RemainingD(IndexAfter)>=MergingThresholds(LoopM)
                                obj.Detection.Data.Remaining(IndexAfter,1) = obj.Detection.Data.AreaBound(SmallAreaBound(SR),1);
                                obj.Detection.Data.AreaBound(SmallAreaBound(SR),:) = NaN;
                            end
                        end
                    end
                end
                obj.Detection.Data.AreaBound(isnan(obj.Detection.Data.AreaBound(:,1)),:) = [];
            end
            
            
            % Prepare logical arrays
            obj.UpdateLogical;
            
            % Replot
            for F = 1 : numel(obj.Detection.ToPlot)
                obj.Replot(obj.Detection.ToPlot{F});
            end
            
            % Enable saving
                obj.Handles.SaveSession_Button.Enable = 'on';
        end

        function EvaluateWindow(obj)
            CurrentPlayingStatus = obj.Playing;
            obj.Playing = false;
            if obj.Handles.DetectionAxes(1).XLim(1)<0,
                obj.Handles.DetectionAxes(1).XLim(1) = 0;
            elseif obj.Handles.DetectionAxes(1).XLim(2)>obj.Times(end),
                obj.Handles.DetectionAxes(1).XLim(2) = obj.Times(end);
            end
            if obj.CurrentTime<obj.Handles.DetectionAxes(1).XLim(1) || obj.CurrentTime>obj.Handles.DetectionAxes(1).XLim(2),
                obj.CurrentTime = obj.Handles.DetectionAxes(1).XLim(1) + 0.5*diff(obj.Handles.DetectionAxes(1).XLim);
                
                for F = numel(obj.Measurements.ToPlot) : -1 : 1,
                    obj.Handles.MeasurementsPlots_TimeLine(F).XData = obj.CurrentTime*[1;1];
                end
                for F = numel(obj.Detection.ToPlot) : -1 : 1,
                    obj.Handles.DetectionPlots_TimeLine(F).XData = obj.CurrentTime*[1;1];
                end
                obj.PlayMovies;
            end
            obj.Playing = CurrentPlayingStatus;
            obj.PlayMovies;
        end
    
        function StartPathCB(obj)
            StartPath = uigetdir(obj.StartPath);
            if StartPath~=0,
                obj.StartPath = [StartPath filesep];
            end
        end
        
        function DrawClosed1CB(obj)
            obj.Handles.ClosedArm(1) = drawpolygon(obj.Handles.Player.Axes,'Color','c');
            obj.ClosedArmMask{1} = obj.Handles.ClosedArm(1).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.ClosedArmVertices{1} = obj.Handles.ClosedArm(1).Position;
            addlistener(obj.Handles.ClosedArm(1),'MovingROI',@(~,~)obj.ReshapeClosed1CB);
            obj.Handles.DrawClosed1_Button.String = 'Delete closed arm #1';
            obj.Handles.DrawClosed1_Button.Callback = {@(~,~)obj.DeleteClosed1CB};
            drawnow
        end
        
        function ReshapeClosed1CB(obj)
            obj.ClosedArmMask{1} = obj.Handles.ClosedArm(1).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.ClosedArmVertices{1} = obj.Handles.ClosedArm(1).Position;
        end
        
        function DeleteClosed1CB(obj)
            delete(obj.Handles.ClosedArm(1));
            obj.ClosedArmMask{1} = [];
            obj.ClosedArmVertices{1} = [];
            obj.Handles.DrawClosed1_Button.String = 'Draw closed arm #1';
            obj.Handles.DrawClosed1_Button.Callback = {@(~,~)obj.DrawClosed1CB};
            drawnow
        end
        
        function DrawWall1CB(obj)
            obj.Handles.Wall(1) = drawpolygon(obj.Handles.Player.Axes,'Color','c');
            obj.WallMask{1} = obj.Handles.Wall(1).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.WallVertices{1} = obj.Handles.Wall(1).Position;
            addlistener(obj.Handles.Wall(1),'MovingROI',@(~,~)obj.ReshapeWall1CB);
            obj.Handles.DrawWall1_Button.String = 'Delete Wall #1';
            obj.Handles.DrawWall1_Button.Callback = {@(~,~)obj.DeleteWall1CB};
            drawnow
        end
        
        function DrawWall2CB(obj)
            obj.Handles.Wall(2) = drawpolygon(obj.Handles.Player.Axes,'Color','c');
            obj.WallMask{2} = obj.Handles.Wall(2).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.WallVertices{2} = obj.Handles.Wall(2).Position;
            addlistener(obj.Handles.Wall(2),'MovingROI',@(~,~)obj.ReshapeWall2CB);
            obj.Handles.DrawWall2_Button.String = 'Delete Wall #2';
            obj.Handles.DrawWall2_Button.Callback = {@(~,~)obj.DeleteWall2CB};
            drawnow
        end
        
        function DrawWallVerticesCB(obj)
            obj.Handles.WallVertices = drawpolygon(obj.Handles.Player.Axes,'Color','c');
            obj.WallVerticesMask = obj.Handles.WallVertices.createMask(obj.Reader.Height,obj.Reader.Width);
            obj.WallVerticesVertices = obj.Handles.WallVertices.Position;
            addlistener(obj.Handles.WallVertices,'MovingROI',@(~,~)obj.ReshapeWallVerticesCB);
            obj.Handles.DrawWallVertices_Button.String = 'Delete walls vertices';
            obj.Handles.DrawWallVertices_Button.Callback = {@(~,~)obj.DeleteWallVerticesCB};
            drawnow
        end
        
        function ReshapeWallVerticesCB(obj)
            obj.WallVerticesMask = obj.Handles.WallVertices.createMask(obj.Reader.Height,obj.Reader.Width);
            obj.WallVerticesVertices = obj.Handles.WallVertices.Position;
        end
        
        function DeleteWallVerticesCB(obj)
            delete(obj.Handles.WallVerticesMask);
            obj.WallVerticesMask = [];
            obj.WallVerticesVertices = [];
            obj.Handles.DrawWallVertices_Button.String = 'Draw walls vertices';
            obj.Handles.DrawWallVertices_Button.Callback = {@(~,~)obj.DrawWallVerticesCB};
            drawnow
        end
        function DrawClosed2CB(obj)
            obj.Handles.ClosedArm(2) = drawpolygon(obj.Handles.Player.Axes,'Color','c');
            obj.ClosedArmMask{2} = obj.Handles.ClosedArm(2).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.ClosedArmVertices{2} = obj.Handles.ClosedArm(2).Position;
            addlistener(obj.Handles.ClosedArm(2),'MovingROI',@(~,~)obj.ReshapeClosed2CB);
            obj.Handles.DrawClosed2_Button.String = 'Delete closed arm #2';
            obj.Handles.DrawClosed2_Button.Callback = {@(~,~)obj.DeleteClosed2CB};
            drawnow
        end
        function ReshapeClosed2CB(obj)
            obj.ClosedArmMask{2} = obj.Handles.ClosedArm(2).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.ClosedArmVertices{2} = obj.Handles.ClosedArm(2).Position;
        end
        
        function DeleteClosed2CB(obj)
            delete(obj.Handles.ClosedArm(2));
            obj.ClosedArmMask{2} = [];
            obj.ClosedArmVertices{2} = [];
            obj.Handles.DrawClosed2_Button.String = 'Draw closed arm #2';
            obj.Handles.DrawClosed2_Button.Callback = {@(~,~)obj.DrawClosed2CB};
            drawnow
        end
        
                     
        function ReshapeWall1CB(obj)
            obj.WallMask{1} = obj.Handles.Wall(1).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.WallVertices{1} = obj.Handles.Wall(1).Position;
        end
        
        function DeleteWall1CB(obj)
            delete(obj.Handles.Wall(1));
            obj.WallMask{1} = [];
            obj.WallVertices{1} = [];
            obj.Handles.DrawWall1_Button.String = 'Draw Wall #1';
            obj.Handles.DrawWall1_Button.Callback = {@(~,~)obj.DrawWall1CB};
            drawnow
        end   
        
        function ReshapeWall2CB(obj)
            obj.WallMask{2} = obj.Handles.Wall(2).createMask(obj.Reader.Height,obj.Reader.Width);
            obj.WallVertices{2} = obj.Handles.Wall(2).Position;
        end
        
        function DeleteWall2CB(obj)
            delete(obj.Handles.Wall(2));
            obj.WallMask{2} = [];
            obj.WallVertices{2} = [];
            obj.Handles.DrawWall2_Button.String = 'Draw Wall #2';
            obj.Handles.DrawWall2_Button.Callback = {@(~,~)obj.DrawWall2CB};
            drawnow
        end
        
        
        
        function UpdateFrame(obj)
            % The refractory toggle switch is here to prevent an event to
            % retrigger the update while it's already being processed; this
            % otherwise prevents keeping the same frame and just updating with
            % the changed parameters
            if ~obj.Refractory
                obj.Refractory = true;
                obj.CurrentTime = obj.CurrentTimeLast;
                obj.PlayMovies;
                obj.Refractory = false;
            end
        end
        
        % Callbacks for the plots
        function EnableContour_CB(obj)
            obj.Enabled.Contour = obj.Handles.UIElements.EnableContour.Value;
            obj.UpdateFrame;
        end
        
        function EnableCenter_CB(obj)
            obj.Enabled.Center = obj.Handles.UIElements.EnableCenter.Value;
            obj.UpdateFrame;
        end
        
        function EnableBodyparts_CB(obj)
            obj.Enabled.Bodyparts = obj.Handles.UIElements.EnableBodyparts.Value;
            if ~isempty(obj.EnabledBodypartsIndex)
                if ~obj.Enabled.Bodyparts
                    for BP = obj.EnabledBodypartsIndex
                        obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.XData = NaN;
                        obj.Handles.BodyParts.(obj.Bodyparts{BP}).W.YData = NaN;
                        obj.Handles.BodyParts.(obj.Bodyparts{BP}).B.XData = NaN;
                        obj.Handles.BodyParts.(obj.Bodyparts{BP}).B.YData = NaN;
                    end
                end
            end
            obj.UpdateFrame;
        end
        
        function EnableZoom_CB(obj)
            obj.Enabled.Zoom = obj.Handles.UIElements.EnableZoom.Value;
            if ~obj.Enabled.Zoom
                % Adjust limits to preserve ratio
                if obj.Reader.Width/obj.Reader.Height >= obj.Handles.Player.AbsolutePosition(3)/obj.Handles.Player.AbsolutePosition(4),
                    % Y needs to be adjusted
                    YDelta = obj.Reader.Width*obj.Handles.Player.AbsolutePosition(4)/obj.Handles.Player.AbsolutePosition(3) - obj.Reader.Height;
                    obj.Handles.Player.Axes.YLim = [1-0.5*YDelta obj.Reader.Height+0.5*YDelta];
                    obj.Handles.Player.Axes.XLim = [1 obj.Reader.Width];
               else
                    % X needs to be adjusted
                    XDelta = obj.Reader.Height*obj.Handles.Player.AbsolutePosition(3)/obj.Handles.Player.AbsolutePosition(4) - obj.Reader.Width;
                    obj.Handles.Player.Axes.XLim = [1-0.5*XDelta obj.Reader.Width+0.5*XDelta];
                    obj.Handles.Player.Axes.YLim = [1 obj.Reader.Height];
                end
            else
                obj.UpdateFrame
            end
        end
        
        function EnableDetectionVisual_CB(obj)
            obj.Enabled.DetectionVisual = obj.Handles.UIElements.EnableDetectionVisual.Value;
            obj.UpdateFrame
        end
        
        function EnableAreaBound_CB(obj)
            obj.Enabled.AreaBound = obj.Handles.UIElements.EnableAreaBound.Value;
            obj.UpdateFrame
        end
        
        function EnableLimits_CB(obj)
            obj.Enabled.Limits = obj.Handles.UIElements.EnableLimits.Value;
            if obj.Enabled.Limits
                hold(obj.Handles.Player.Axes,'on')
                obj.Handles.Rearing.Contours_ZeroRing.Color = obj.PlotParameters.RearingLimitsColor.ZeroRing;
                obj.Handles.Rearing.Contours_FirstRing.Color = obj.PlotParameters.RearingLimitsColor.FirstRing;
                obj.Handles.Rearing.Contours_SecondRing.Color = obj.PlotParameters.RearingLimitsColor.SecondRing;
                pause(0.01);
                if contains(obj.Basename,'EPM')
                    obj.Handles.HeadDips.Contours_ZeroRing.Color = obj.PlotParameters.HeadDipsLimitsColor.ZeroRing;
                    obj.Handles.HeadDips.Contours_FirstRing.Color = obj.PlotParameters.HeadDipsLimitsColor.FirstRing;
                    obj.Handles.HeadDips.Contours_SecondRing.Color = obj.PlotParameters.HeadDipsLimitsColor.SecondRing;
                end
                
            else
                obj.Handles.Rearing.Contours_ZeroRing.Color = 'none';
                obj.Handles.Rearing.Contours_FirstRing.Color = 'none';
                obj.Handles.Rearing.Contours_SecondRing.Color = 'none';
                if contains(obj.Basename,'EPM')
                    obj.Handles.HeadDips.Contours_ZeroRing.Color = 'none';
                    obj.Handles.HeadDips.Contours_FirstRing.Color = 'none';
                    obj.Handles.HeadDips.Contours_SecondRing .Color = 'none';
                end
            end
        end                            

        % Processing updates
        function StretchAttend_LengthThresholdCB(obj)
            if ~obj.Dragging
                obj.Dragging = true;
                obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingStretchAttendLengthSlider;
                obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.StretchAttend_LengthThresholdCB;
            else
                obj.Dragging = false;
                obj.Parameters.StretchAttend.Length = obj.Handles.StretchAttend_LengthThreshold.Parent.CurrentPoint(3)/obj.Parameters.SizeCorrection;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
                
                SAT =  obj.Parameters.StretchAttend.BothHindPaws;
                SATHigh = obj.Parameters.StretchAttend.SingleHindPaw;
                StretchAttend = (...
                    obj.Measurements.Data.TotalLength>obj.Parameters.StretchAttend.Length * obj.Parameters.SizeCorrection) & smoothdata(obj.Measurements.Data.StepSpeed,'gaussian',5)<obj.Parameters.StretchAttend.StepSpeed &...
                    ((obj.Measurements.Data.HindPawRight<SAT & obj.Measurements.Data.HindPawLeft<SAT) | (obj.Measurements.Data.HindPawLeft<SAT & (obj.Score.HindPawRight<0.9 | obj.Score.HindPawRight<SATHigh)) | (obj.Measurements.Data.HindPawRight<SAT &...
                    (obj.Score.HindPawLeft<0.9 | obj.Measurements.Data.HindPawLeft<SATHigh))) ;
                obj.Detection.Data.StretchAttend = obj.GetRanges(StretchAttend,obj.Parameters.StretchAttend.Merging,obj.Parameters.StretchAttend.MinimumDuration);
                
                delete(obj.Handles.DetectionRanges.StretchAttend)
                SAP_Axes = find(arrayfun(@(x) contains(obj.Handles.DetectionAxes(x).YLabel.String,'StretchAttend'),1:numel(obj.Handles.DetectionAxes)));
                DC = DefColors;
                obj.Handles.DetectionRanges.StretchAttend = arrayfun(@(x) fill(obj.Detection.Data.StretchAttend(x,[1 2 2 1]),[0 0 1 1],DC(SAP_Axes,:),'EdgeColor',DC(SAP_Axes,:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(SAP_Axes),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag','StretchAttend','UserData',num2str(x)),1:size(obj.Detection.Data.StretchAttend,1));
                obj.UpdateLogical;
                
                % Enable saving
                obj.Handles.SaveSession_Button.Enable = 'off';
            end
        end
        
        function MovingStretchAttendLengthSlider(obj)
            obj.Handles.StretchAttend_LengthThreshold.YData = [1 1]*obj.Handles.StretchAttend_LengthThreshold.Parent.CurrentPoint(3);
        end
        
        function Grooming_ThresholdCB(obj)
            if ~obj.Dragging
                obj.Dragging = true;
                obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingGrooming_ThresholdSlider;
                obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.Grooming_ThresholdCB;
            else
                obj.Dragging = false;
                obj.Parameters.Grooming.Threshold = obj.Handles.Grooming_Threshold.Parent.CurrentPoint(3);
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
                
                IndxGrooming = find(obj.Measurements.Data.Grooming<obj.Parameters.Grooming.Threshold &...
                    obj.Measurements.Data.StepSpeed<obj.Parameters.Grooming.MaxStepSpeed &...
                    obj.Measurements.Data.Motion>obj.Parameters.Grooming.LowMotion);
                Ranges = FindContinuousRange(IndxGrooming);
                
                if Ranges(1,3) == 0
                    Ranges = [NaN NaN];
                else
                    for RG = 1 : size(Ranges,1)-1
                        % Merge if just NaN between
                        if all(isnan(obj.Measurements.Data.Grooming(IndxGrooming(Ranges(RG,2))+1:IndxGrooming(Ranges(RG+1,1))-1)))
                            Ranges(RG+1,1) = Ranges(RG,1);
                            Ranges(RG,:) = NaN;
                        end
                    end
                    Ranges = Ranges(~isnan(Ranges(:,1)),:);
                    Ranges = obj.Times(IndxGrooming(Ranges(:,[1 2])));
                    
                    
                    % Merging if close
                    if ~isempty(Ranges),
                        if size(Ranges,2)==1,
                            Ranges = Ranges';
                        else
                            for RG = 1 : size(Ranges,1)-1,
                                % Merge if just NaN between
                                if (Ranges(RG+1,1) - Ranges(RG,2))<=obj.Parameters.Grooming.Merging
                                    Ranges(RG+1,1) = Ranges(RG,1);
                                    Ranges(RG,:) = NaN;
                                end
                            end
                            Ranges = Ranges(~isnan(Ranges(:,1)),:);
                        end
                        
                        % Minimum duration
                        Ranges(diff(Ranges,[],2)<obj.Parameters.Grooming.MinimumDuration,:) = [];
                        if isempty(Ranges),
                            Ranges = [NaN NaN];
                        elseif numel(Ranges)== 2 && size(Ranges,1) == 2,
                            Ranges = Ranges';
                        end
                    else
                        Ranges = [NaN NaN];
                    end
                    
                end
                obj.Detection.Data.Grooming = Ranges;
                
                
                delete(obj.Handles.DetectionRanges.Grooming)
                Grooming_Axes = find(arrayfun(@(x) contains(obj.Handles.DetectionAxes(x).YLabel.String,'Grooming'),1:numel(obj.Handles.DetectionAxes)));
                DC = DefColors;
                obj.Handles.DetectionRanges.Grooming = arrayfun(@(x) fill(obj.Detection.Data.Grooming(x,[1 2 2 1]),[0 0 1 1],DC(Grooming_Axes,:),'EdgeColor',DC(Grooming_Axes,:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(Grooming_Axes),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag','Grooming','UserData',num2str(x)),1:size(obj.Detection.Data.Grooming,1));
                obj.UpdateLogical;
                % Enable saving
                obj.Handles.SaveSession_Button.Enable = 'off';
            end
        end
        
        function MovingGrooming_ThresholdSlider(obj)
            obj.Handles.Grooming_Threshold.YData = [1 1]*obj.Handles.Grooming_Threshold.Parent.CurrentPoint(3);
        end
        
        function TailRattling_TailMotionThresholdCB(obj)
            if ~obj.Dragging
                obj.Dragging = true;
                obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingTailRattlingThresholdSlider;
                obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.TailRattling_TailMotionThresholdCB;
            else
                obj.Dragging = false;
                obj.Parameters.TailRattling.Threshold = obj.Handles.TailRattling_TailMotionThreshold.Parent.CurrentPoint(3);
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
                
                TailRattling = obj.Measurements.Data.TailMotion>obj.Parameters.TailRattling.Threshold & obj.Measurements.Data.StepSpeed<obj.Parameters.TailRattling.MaxStepSpeedBody & obj.Measurements.Data.(obj.Parameters.TailRattling.Reference).StepSpeed < obj.Parameters.TailRattling.MaxStepSpeedMoving;
                obj.Detection.Data.TailRattling = obj.GetRanges(TailRattling,obj.Parameters.TailRattling.Merging,obj.Parameters.TailRattling.MinimumDuration);
                
                delete(obj.Handles.DetectionRanges.TailRattling)
                SAP_Axes = find(arrayfun(@(x) contains(obj.Handles.DetectionAxes(x).YLabel.String,'TailRattling'),1:numel(obj.Handles.DetectionAxes)));
                DC = DefColors;
                obj.Handles.DetectionRanges.TailRattling = arrayfun(@(x) fill(obj.Detection.Data.TailRattling(x,[1 2 2 1]),[0 0 1 1],DC(SAP_Axes,:),'EdgeColor',DC(SAP_Axes,:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(SAP_Axes),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag','TailRattling','UserData',num2str(x)),1:size(obj.Detection.Data.TailRattling,1));
                obj.UpdateLogical;
                % Enable saving
                obj.Handles.SaveSession_Button.Enable = 'off';
            end
        end
         
        function MovingTailRattlingThresholdSlider(obj)
            obj.Handles.TailRattling_TailMotionThreshold.YData = [1 1]*obj.Handles.TailRattling_TailMotionThreshold.Parent.CurrentPoint(3);
        end
            
        
        function RangeEditCB(obj,src,~)
            if ~obj.Editing
                obj.Editing = true;
                % Swith the editable mode: lines on the sides and body as a
                % line too
                XData = unique(src.XData);
                YData = unique(src.YData);
                hold(src.Parent,'on')
                obj.CurrentEdit = src;
                obj.Handles.CurrentEdition.LineM = plot(XData,[1 1] * mean(YData),'k','LineWidth',4,'Parent',src.Parent,'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)});
                obj.Handles.CurrentEdition.LineB = plot([XData(1) XData(1)],YData,'k','LineWidth',3,'Parent',src.Parent,'ButtonDownFcn',@(~,~)obj.DragLineB);
                obj.Handles.CurrentEdition.LineE = plot([XData(2) XData(2)],YData,'k','LineWidth',3,'Parent',src.Parent,'ButtonDownFcn',@(~,~)obj.DragLineE);
                obj.Handles.DeleteRange_Button.Enable = 'on';
                obj.Handles.DeleteRange_Button.Visible = 'on';
                if strcmpi(src.Parent.YLabel.String,'Grooming')
                    obj.Handles.ChangeRange_Button.Enable = 'on';
                    obj.Handles.ChangeRange_Button.Visible = 'on';
                end
            else
                obj.Editing = false;
                if strcmpi(obj.CurrentEdit.Parent.YLabel.String,'Grooming')
                    obj.Handles.ChangeRange_Button.Enable = 'off';
                    obj.Handles.ChangeRange_Button.Visible = 'off';
                end
                OriginalRange =  obj.Detection.Data.(obj.CurrentEdit.Tag)(str2double(obj.CurrentEdit.UserData),:);
                NewRange = (sort(obj.CurrentEdit.XData(1:2)))';
                obj.Detection.Data.(obj.CurrentEdit.Tag)(str2double(obj.CurrentEdit.UserData),:) = (sort(obj.CurrentEdit.XData(1:2)))';
                % Apply changes to the other behaviours' data and plots
                Fields = fields(obj.Detection.Data);
                % Case 1: shortened from the beginning
                if NewRange(1)>OriginalRange(1)
                    % Find the behaviour just before the original range
                    PrevTime = obj.Times(find(obj.Times<OriginalRange(1),1,'last'));
                    NewEndTime = obj.Times(find(obj.Times<NewRange(1),1,'last'));
                    for Fi = 1 : numel(Fields)
                        if ~isempty(obj.Detection.Data.(Fields{Fi})) && any(obj.Detection.Data.(Fields{Fi})(:,2)==PrevTime)
                            obj.Detection.Data.(Fields{Fi})(obj.Detection.Data.(Fields{Fi})(:,2)==PrevTime,2) = NewEndTime;
                            obj.Replot(Fields{Fi})
                            break
                        end
                    end
                end
                % Case 2: shortened from the end
                if NewRange(2)<OriginalRange(2)
                    % Find the behaviour just after the original range
                    NextTime = obj.Times(find(obj.Times>OriginalRange(2),1,'first'));
                    NewStartTime = obj.Times(find(obj.Times>NewRange(2),1,'first'));
                    for Fi = 1 : numel(Fields)
                        if ~isempty(obj.Detection.Data.(Fields{Fi})) && any(obj.Detection.Data.(Fields{Fi})(:,1)==NextTime)
                            obj.Detection.Data.(Fields{Fi})(obj.Detection.Data.(Fields{Fi})(:,1)==NextTime,1) = NewStartTime;
                            obj.Replot(Fields{Fi})
                            break
                        end
                    end
                end
                % Case 3: extended at the beginning
                if NewRange(1)<OriginalRange(1)
                    NewEndTime = obj.Times(find(obj.Times<NewRange(1),1,'last'));
                    for Fi = 1 : numel(Fields)
                        if ~isempty(obj.Detection.Data.(Fields{Fi}))
                            % Completely included in new range
                            IndxInc = obj.Detection.Data.(Fields{Fi})(:,1)>=NewRange(1) & obj.Detection.Data.(Fields{Fi})(:,2)<OriginalRange(1) & ~(obj.Detection.Data.(Fields{Fi})(:,1)==NewRange(1) & obj.Detection.Data.(Fields{Fi})(:,2)==NewRange(2));
                            if ~isempty(IndxInc)
                                obj.Detection.Data.(Fields{Fi})(IndxInc,:) = [];
                            end
                            % Overlap
                            IndxInc = obj.Detection.Data.(Fields{Fi})(:,1)<NewRange(1) & obj.Detection.Data.(Fields{Fi})(:,2)>NewRange(1);
                            if ~isempty(IndxInc)
                                obj.Detection.Data.(Fields{Fi})(IndxInc,2) = NewEndTime;
                            end
                            obj.Replot(Fields{Fi})
                        end
                    end
                end
                % Case 4: extended at the end
                if NewRange(2)>OriginalRange(2)
                    NewStartTime = obj.Times(find(obj.Times>NewRange(2),1,'first'));
                    for Fi = 1 : numel(Fields)
                        if ~isempty(obj.Detection.Data.(Fields{Fi}))
                            % Completely included in new range
                            IndxInc = obj.Detection.Data.(Fields{Fi})(:,1)<=NewRange(2) & obj.Detection.Data.(Fields{Fi})(:,2)>OriginalRange(2) & ~(obj.Detection.Data.(Fields{Fi})(:,1)==NewRange(1) & obj.Detection.Data.(Fields{Fi})(:,2)==NewRange(2));
                            if ~isempty(IndxInc)
                                obj.Detection.Data.(Fields{Fi})(IndxInc,:) = [];
                            end
                            % Overlap
                            IndxInc = obj.Detection.Data.(Fields{Fi})(:,1)<NewRange(1) & obj.Detection.Data.(Fields{Fi})(:,2)>NewRange(1);
                            if ~isempty(IndxInc)
                                obj.Detection.Data.(Fields{Fi})(IndxInc,1) = NewStartTime;
                            end
                            obj.Replot(Fields{Fi})
                        end
                    end
                end
                
                delete(obj.Handles.CurrentEdition.LineB)
                delete(obj.Handles.CurrentEdition.LineE)
                delete(obj.Handles.CurrentEdition.LineM)
                obj.Handles.DeleteRange_Button.Enable = 'off';
                obj.Handles.DeleteRange_Button.Visible = 'off';
                drawnow
                obj.UpdateLogical;
            end
        end
        
        
        function DragLineB(obj)
            if ~obj.Dragging
                obj.Dragging = true;
                obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingLineB;
                obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.DragLineB;
            else
                obj.Dragging = false;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
            end
        end
        
        
        function MovingLineB(obj)
            CurrentX = obj.Handles.CurrentEdition.LineB.Parent.CurrentPoint(1);
            obj.CurrentEdit.XData([1 4]) = [CurrentX CurrentX];
            obj.Handles.CurrentEdition.LineB.XData = [CurrentX CurrentX];
            obj.Handles.CurrentEdition.LineM.XData(1) = CurrentX;
            if ~obj.Refractory
                obj.Refractory = true;
                obj.CurrentTime = CurrentX;
                obj.PlayMovies;
                obj.Refractory = false;
            end
        end
        
        function DragLineE(obj)
            if ~obj.Dragging
                obj.Dragging = true;
                obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingLineE;
                obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.DragLineE;
            else
                obj.Dragging = false;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
            end
        end
        
        function MovingLineE(obj)
            CurrentX = obj.Handles.CurrentEdition.LineE.Parent.CurrentPoint(1);
            obj.CurrentEdit.XData([2 3]) = [CurrentX CurrentX];
            obj.Handles.CurrentEdition.LineE.XData = [CurrentX CurrentX];
            obj.Handles.CurrentEdition.LineM.XData(2) = CurrentX;
            if ~obj.Refractory
                obj.Refractory = true;
                obj.CurrentTime = CurrentX;
                obj.PlayMovies;
                obj.Refractory = false;
            end
        end
        
        function InsertRangeCB(obj)
            if numel(obj.SelectedDetection)~=1
                return
            end
            for F = numel(obj.Detection.ToPlot) : -1 : 1
                obj.Handles.DetectionAxes(F).ButtonDownFcn = [];
            end
            Selected_Axes = find(arrayfun(@(x) strcmpi(obj.Handles.DetectionAxes(x).YLabel.String,obj.SelectedDetection),1:numel(obj.Handles.DetectionAxes)));
            NewRange = drawrectangle(obj.Handles.DetectionAxes(Selected_Axes));
            obj.Detection.Data.(obj.SelectedDetection{1}) = [obj.Detection.Data.(obj.SelectedDetection{1}); [NewRange.Position(1) NewRange.Position(1)+NewRange.Position(3)]];
            DC = DefColors;
            DC = repmat(DC,10,1);
            NewPatch = fill([NewRange.Position(1) NewRange.Position(1)+NewRange.Position(3) NewRange.Position(1)+NewRange.Position(3) NewRange.Position(1)],[0 0 1 1],DC(str2double(obj.Handles.DetectionAxes(Selected_Axes).Tag),:),'EdgeColor',DC(str2double(obj.Handles.DetectionAxes(Selected_Axes).Tag),:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(Selected_Axes),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag',obj.SelectedDetection{1},'UserData',num2str(numel(obj.Handles.DetectionRanges.(obj.SelectedDetection{1})) +1));
            obj.Handles.DetectionRanges.(obj.SelectedDetection{1}) = [obj.Handles.DetectionRanges.(obj.SelectedDetection{1}) NewPatch];
            delete(NewRange)
            for F = numel(obj.Detection.ToPlot) : -1 : 1
                obj.Handles.DetectionAxes(F).ButtonDownFcn = {@(src,evt)obj.SelectAxes(src,evt)};
                uistack(obj.Handles.DetectionPlots_TimeLine(F),'top')
            end
            obj.UpdateLogical;
        end
    
        function DeleteRangeCB(obj)
            obj.CurrentEdit.XData = NaN(1,4);
            obj.RangeEditCB;
            obj.UpdateLogical;
        end
        
        function ChangeRangeCB(obj)
            IndxA = arrayfun(@(x) strcmpi(obj.Handles.DetectionAxes(x).YLabel.String,'OpenRearing'),1:numel(obj.Handles.DetectionAxes));
            if any(IndxA)
                obj.Detection.Data.OpenRearing = [obj.Detection.Data.OpenRearing; (obj.CurrentEdit.XData([1 3]))'];
                F = str2double(obj.Handles.DetectionAxes(IndxA).Tag);
                DC = DefColors;
                DC = repmat(DC,5,1);
                obj.Handles.DetectionRanges.OpenRearing = [obj.Handles.DetectionRanges.OpenRearing, fill(obj.CurrentEdit.XData',[0 0 1 1],DC(F,:),'EdgeColor',DC(F,:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(F),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag',obj.Detection.ToPlot{F},'UserData',num2str(numel(obj.Handles.DetectionRanges.OpenRearing) +1))];
                obj.CurrentEdit.XData = NaN(1,4);
                obj.RangeEditCB;
                obj.UpdateLogical;
            else
                obj.Detection.ToPlot = [obj.Detection.ToPlot,'OpenRearing'];
                obj.Detection.Data.OpenRearing = (obj.CurrentEdit.XData([1 3]))';
                obj.CurrentEdit.XData = NaN(1,4);
                obj.Detection.Data.(obj.CurrentEdit.Tag)(str2double(obj.CurrentEdit.UserData),:) = (obj.CurrentEdit.XData(1:2))';

                % Update detection plots
                if isfield(obj.Handles,'DetectionAxes')
                    delete(obj.Handles.DetectionAxes(:))
                    obj.Handles = rmfield(obj.Handles,'DetectionAxes');
                end
                if ~isempty(obj.Detection.ToPlot)
                    DC = DefColors;
                    DC = repmat(DC,5,1);
                    for F = numel(obj.Detection.ToPlot) : -1 : 1
                        obj.Handles.DetectionAxes(F) = axes('Units','normalized','Position',[0.08 0.285-F*(0.2/numel(obj.Detection.ToPlot)) 0.42 0.2/numel(obj.Detection.ToPlot)],'Color','w','Tag',num2str(F)); hold on
                        obj.Handles.DetectionAxes(F).ButtonDownFcn = {@(src,evt)obj.SelectAxes(src,evt)};
                        hold on
                        if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{F})) 
                            obj.Handles.DetectionRanges.(obj.Detection.ToPlot{F}) = arrayfun(@(x) fill(obj.Detection.Data.(obj.Detection.ToPlot{F})(x,[1 2 2 1]),[0 0 1 1],DC(F,:),'EdgeColor',DC(F,:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(F),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag',obj.Detection.ToPlot{F},'UserData',num2str(x)),1:size(obj.Detection.Data.(obj.Detection.ToPlot{F}),1));
                        else
                            obj.Handles.DetectionRanges.(obj.Detection.ToPlot{F}) = [];
                        end
                        obj.Handles.DetectionPlots_TimeLine(F) = plot(obj.CurrentTime*[1;1],[-0.25 1.25],'k','LineWidth',3,'Parent',obj.Handles.DetectionAxes(F),...
                            'ButtonDownFcn',{@(src,evt)obj.SliderCB(src,evt)});
                    end
                    if numel(obj.Detection.ToPlot)>1
                        for F = 1 : numel(obj.Detection.ToPlot)-1
                            obj.Handles.DetectionAxes(F).XAxis.Visible = 'off';
                        end
                    end
                    for F = 1 : numel(obj.Detection.ToPlot)
                        obj.Handles.DetectionAxes(F).LineWidth = 3;
                        obj.Handles.DetectionAxes(F).FontSize = 13;
                        obj.Handles.DetectionAxes(F).FontWeight = 'b';
                        obj.Handles.DetectionAxes(F).TickDir = 'out';
                        obj.Handles.DetectionAxes(F).YLabel.String = obj.Detection.ToPlot{F};
                        obj.Handles.DetectionAxes(F).YTick = [];
                        obj.Handles.DetectionAxes(F).YLabel.Rotation = 0;
                        obj.Handles.DetectionAxes(F).YLabel.Color = 'k';
                        obj.Handles.DetectionAxes(F).YLabel.HorizontalAlignment = 'right';
                        obj.Handles.DetectionAxes(F).YLabel.VerticalAlignment = 'middle';
                        obj.Handles.DetectionAxes(F).YLim = [-0.25 1.25];
                        ZoomHandleSubF = zoom(obj.Handles.DetectionAxes(F));
                        ZoomHandleSubF.Motion = 'horizontal';
                        ZoomHandleSubF.ActionPostCallback = @(~,~)obj.EvaluateWindow;
                        obj.Handles.DetectionAxes(F).Toolbar.Visible = 'off';
                    end
                    obj.Handles.DetectionAxes(1).Toolbar.Visible = 'on';
                    obj.Handles.DetectionAxes(numel(obj.Detection.ToPlot)).XLabel.String = 'Time (s)';
                    for AxL = 1 : numel(obj.Handles.MeasurementsAxes)
                        ZoomHandleSub = zoom(obj.Handles.MeasurementsAxes(AxL));
                        ZoomHandleSub.ActionPostCallback = @(~,~)obj.EvaluateWindow;
                        ZoomHandleSubF.Motion = 'both';
                    end
                    linkaxes([obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes],'x')
                    Subs = [obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes];
                    obj.Handles.FillRemovedWindows{numel(Subs)} = [];
                    for S = 1 : numel(Subs)
                        obj.Handles.LineStartRemovedWindows{S} = [];
                        obj.Handles.LineEndRemovedWindows{S} = [];
                        delete(obj.Handles.FillRemovedWindows{S})
                        if isempty(obj.ExclusionRanges)
                            obj.Handles.FillRemovedWindows{S} = [];
                        else
                            obj.Handles.FillRemovedWindows{S} = arrayfun(@(x) fill([obj.ExclusionRanges(x,1) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,1)], [Subs(S).YLim(1) * [1 1]  Subs(S).YLim(2) * [1 1]],[0.85 0.9 0.85],'FaceAlpha',0.5,'EdgeColor','none','Parent',Subs(S),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.ExclusionRanges(:,1)));
                            uistack(obj.Handles.FillRemovedWindows{S},'bottom')
                        end
                    end
                    obj.SelectedDetection = [];
                    
                    t = linspace(0,2*pi);
                    % Make patch
                    DC = DefColors;
                    DC = repmat(DC,5,1);
                    obj.Handles.OverlayDetection(numel(obj.Detection.ToPlot)) = obj.Handles.OverlayDetection(1);
                    YL = obj.Handles.OverlayAxes.YLim;
                    for DT = 1 : numel(obj.Detection.ToPlot)
                        if ~contains(obj.ExcludePlot,obj.Detection.ToPlot{DT})
                            delete(obj.Handles.OverlayDetection(DT))
                            Radius_Out = YL(2)/2 - (DT-1)*YL(2)/2*obj.PlotParameters.OverlayBandWidth/100;
                            Radius_In = Radius_Out-YL(2)/2*obj.PlotParameters.OverlayBandWidth/100;
                            xin = 50 + Radius_In*cos(t);
                            xout = 50 + Radius_Out*cos(t);
                            yin = YL(2)/2 + Radius_In*sin(t);
                            yout = YL(2)/2 + Radius_Out*sin(t);
                            obj.Handles.OverlayDetection(DT) = fill([xout,xin],[yout,yin],DC(DT,:),'linestyle','none','facealpha',obj.PlotParameters.OverlayFaceAplha,'Visible','off','Parent',obj.Handles.OverlayAxes);
                        end
                    end
                end
                obj.Handles.ChangeRange_Button.Enable = 'off';
                obj.Handles.ChangeRange_Button.Visible = 'off';
                obj.Handles.DeleteRange_Button.Enable = 'off';
                obj.Handles.DeleteRange_Button.Visible = 'off';
                obj.Handles.InsertRange_Button.Enable = 'off';
                obj.Handles.InsertRange_Button.Visible = 'off';
                obj.Editing = false;
            end
            obj.UpdateLogical;
        end
        
        function SelectAxes(obj,src,~)
            if isempty(obj.SelectedDetection)
                src.YLabel.Color = 'w';
                src.Color = [0.9 0.9 0.9];
                obj.SelectedDetection = {src.YLabel.String};
            else
                IndxR = arrayfun(@(x)strcmpi(obj.SelectedDetection{x},src.YLabel.String),1:numel(obj.SelectedDetection));
                if any(IndxR)
                    obj.SelectedDetection = obj.SelectedDetection(~IndxR);
                    src.YLabel.Color = 'k';
                    src.Color = 'w';
                else
                    src.YLabel.Color = 'w';
                    src.Color = [0.9 0.9 0.9];
                    obj.SelectedDetection = [obj.SelectedDetection,src.YLabel.String];
                end
            end
            if numel(obj.SelectedDetection) ==1
                obj.Handles.InsertRange_Button.Enable = 'on';
                obj.Handles.InsertRange_Button.Visible = 'on';
            else
                obj.Handles.InsertRange_Button.Enable = 'off';
                obj.Handles.InsertRange_Button.Visible = 'off';
            end
        end
        
        function PlayNextRange(obj)
            drawnow
            if isempty(obj.PreState)
                obj.PreState = obj.Playing;
            end
            if ~isempty(obj.SelectedDetection)
                % We pick the current time as starting point to look for
                % the next range in the selected detection only
                DetData = [];
                for S = 1 : numel(obj.SelectedDetection)
                    DetData = [DetData;obj.Detection.Data.(obj.SelectedDetection{S})];
                end
            else
                % We pick the current time as starting point to look for
                % the next range in all detections
                DetData = [];
                
                for S = 1 : numel(obj.Handles.DetectionAxes)
                    DetData = [DetData;obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String)];
                end
            end
            if ~isempty(obj.CurrentlyPlaying)
                DetData(DetData(:,1) == obj.CurrentlyPlaying,:) = NaN;
            end
            
            Diff =  DetData(:,1)- obj.CurrentTime - obj.PlotParameters.PreTime;
            if all(Diff<0 | isnan(Diff))
                [~,IndxM] = min(DetData(:,1));
            else
                Diff(Diff<0) = NaN;
                [~,IndxM] = min(Diff);
            end
            
            if ~(isempty(IndxM)||isnan(IndxM))
                obj.CurrentlyPlaying = DetData(IndxM,1);
                if ~obj.Playing
                    obj.CurrentTime = DetData(IndxM,1) - obj.PlotParameters.PreTime;
                    obj.Play_CB('Timed',DetData(IndxM,2)+obj.PlotParameters.PostTime);
                elseif obj.PreState
                    obj.CurrentTime = DetData(IndxM,1) - obj.PlotParameters.PreTime;
                else
                    obj.Playing = false;
                    obj.CurrentTime = DetData(IndxM,1) - obj.PlotParameters.PreTime;
                    obj.Play_CB('Timed',DetData(IndxM,2)+obj.PlotParameters.PostTime);
                end
            end
            obj.CurrentlyPlaying = [];
            obj.PreState = [];
        end
        
        
        
        function PlayPreviousRange(obj)
            drawnow
            if isempty(obj.PreState)
                obj.PreState = obj.Playing;
            end
            if ~isempty(obj.SelectedDetection)
                % We pick the current time as starting point to look for
                % the next range in the selected detection only
                DetData = [];
                for S = 1 : numel(obj.SelectedDetection)
                    DetData = [DetData;obj.Detection.Data.(obj.SelectedDetection{S})];
                end
            else
                % We pick the current time as starting point to look for
                % the next range in all detections
                DetData = [];
                
                for S = 1 : numel(obj.Handles.DetectionAxes)
                    DetData = [DetData;obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String)];
                end
            end
            if ~isempty(obj.CurrentlyPlaying)
                DetData(DetData(:,1) == obj.CurrentlyPlaying,:) = NaN;
            end
            
            Diff =  DetData(:,1)- obj.CurrentTime;
            if all(Diff>0 | isnan(Diff))
                [~,IndxM] = max(abs(DetData(:,1)));
            else
                Diff(Diff>0) = NaN;
                [~,IndxM] = min(abs(Diff));
            end
            
            if ~(isempty(IndxM)||isnan(IndxM))
                obj.CurrentlyPlaying = DetData(IndxM,1);
                if ~obj.Playing
                    obj.CurrentTime = DetData(IndxM,1) - obj.PlotParameters.PreTime;
                    obj.Play_CB('Timed',DetData(IndxM,2)+obj.PlotParameters.PostTime);
                elseif obj.PreState
                    obj.CurrentTime = DetData(IndxM,1) - obj.PlotParameters.PreTime;
                else
                    obj.Playing = false;
                    obj.CurrentTime = DetData(IndxM,1) - obj.PlotParameters.PreTime;
                    obj.Play_CB('Timed',DetData(IndxM,2)+obj.PlotParameters.PostTime);
                end
            end
            obj.CurrentlyPlaying = [];
            obj.PreState = [];
        end
        
        function EditNext(obj)
            drawnow
            if ~isempty(obj.SelectedDetection)
                % We pick the current time as starting point to look for
                % the next range in the selected detection only
                DetData = [];
                DetectType = {};
                IndxDetect = [];
                DetectType = {};
                Prev = 0;
                for S = 1 : numel(obj.SelectedDetection)
                    if ~isempty(obj.Detection.Data.(obj.SelectedDetection{S}))
                        DetData = [DetData;obj.Detection.Data.(obj.SelectedDetection{S})];
                        DetectType(Prev+1:Prev+size(obj.Detection.Data.(obj.SelectedDetection{S}),1)) = repmat({obj.SelectedDetection{S}},size(obj.Detection.Data.(obj.SelectedDetection{S}),1),1);
                        Prev = numel(DetectType);
                        IndxDetect = [IndxDetect;(1:size(obj.Detection.Data.(obj.SelectedDetection{S}),1))'];
                    end
                end
            else
                % We pick the current time as starting point to look for
                % the next range in all detections
                DetData = [];
                IndxDetect = [];
                DetectType = {};
                Prev = 0;
                for S = 1 : numel(obj.Handles.DetectionAxes)
                    if ~isempty(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String))
                        DetData = [DetData;obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String)];
                        DetectType(Prev+1:Prev+size(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String),1)) = repmat({obj.Handles.DetectionAxes(S).YLabel.String},size(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String),1),1);
                        Prev = numel(DetectType);
                        IndxDetect = [IndxDetect;(1:size(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String),1))'];
                    end
                end
            end
            
            Diff =  DetData(:,1)- obj.CurrentEdit.XData(1);
            if all(Diff<=0 | isnan(Diff))
                [~,IndxM] = min(DetData(:,1));
            else
                Diff(Diff<=0) = NaN;
                [~,IndxM] = min(Diff);
            end
            
            if ~(isempty(IndxM)||isnan(IndxM))
                obj.RangeEditCB;
                src =  obj.Handles.DetectionRanges.(DetectType{IndxM})(IndxDetect(IndxM));
                obj.Editing = true;
                % Swith the editable mode: lines on the sides and body as a
                % line too
                XData = unique(src.XData);
                YData = unique(src.YData);
                hold(src.Parent,'on')
                obj.CurrentEdit = src;
                obj.Handles.CurrentEdition.LineM = plot(XData,[1 1] * mean(YData),'k','LineWidth',4,'Parent',src.Parent,'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)});
                obj.Handles.CurrentEdition.LineB = plot([XData(1) XData(1)],YData,'k','LineWidth',3,'Parent',src.Parent,'ButtonDownFcn',@(~,~)obj.DragLineB);
                obj.Handles.CurrentEdition.LineE = plot([XData(2) XData(2)],YData,'k','LineWidth',3,'Parent',src.Parent,'ButtonDownFcn',@(~,~)obj.DragLineE);
                obj.Handles.DeleteRange_Button.Enable = 'on';
                obj.Handles.DeleteRange_Button.Visible = 'on';
                if strcmpi(src.Parent.YLabel.String,'Grooming')
                    obj.Handles.ChangeRange_Button.Enable = 'on';
                    obj.Handles.ChangeRange_Button.Visible = 'on';
                end
            end
        end
        
        function EditPrevious(obj)
            drawnow
            if ~isempty(obj.SelectedDetection)
                % We pick the current time as starting point to look for
                % the next range in the selected detection only
                DetData = [];
                DetectType = {};
                IndxDetect = [];
                DetectType = {};
                Prev = 0;
                for S = 1 : numel(obj.SelectedDetection)
                    if ~isempty(obj.Detection.Data.(obj.SelectedDetection{S}))
                        DetData = [DetData;obj.Detection.Data.(obj.SelectedDetection{S})];
                        DetectType(Prev+1:Prev+size(obj.Detection.Data.(obj.SelectedDetection{S}),1)) = repmat({obj.SelectedDetection{S}},size(obj.Detection.Data.(obj.SelectedDetection{S}),1),1);
                        Prev = numel(DetectType);
                        IndxDetect = [IndxDetect;(1:size(obj.Detection.Data.(obj.SelectedDetection{S}),1))'];
                    end
                end
            else
                % We pick the current time as starting point to look for
                % the next range in all detections
                DetData = [];
                IndxDetect = [];
                DetectType = {};
                Prev = 0;
                for S = 1 : numel(obj.Handles.DetectionAxes)
                    if ~isempty(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String))
                        DetData = [DetData;obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String)];
                        DetectType(Prev+1:Prev+size(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String),1)) = repmat({obj.Handles.DetectionAxes(S).YLabel.String},size(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String),1),1);
                        Prev = numel(DetectType);
                        IndxDetect = [IndxDetect;(1:size(obj.Detection.Data.(obj.Handles.DetectionAxes(S).YLabel.String),1))'];
                    end
                end
            end
            
            Diff =  DetData(:,1)- obj.CurrentEdit.XData(1);
            if all(Diff>0 | isnan(Diff))
                [~,IndxM] = max(DetData(:,1));
            else
                Diff(Diff>=0) = NaN;
                [~,IndxM] = min(abs(Diff));
            end
            
            if ~(isempty(IndxM)||isnan(IndxM))
                obj.RangeEditCB;
                src =  obj.Handles.DetectionRanges.(DetectType{IndxM})(IndxDetect(IndxM));
                obj.Editing = true;
                % Swith the editable mode: lines on the sides and body as a
                % line too
                XData = unique(src.XData);
                YData = unique(src.YData);
                hold(src.Parent,'on')
                obj.CurrentEdit = src;
                obj.Handles.CurrentEdition.LineM = plot(XData,[1 1] * mean(YData),'k','LineWidth',4,'Parent',src.Parent,'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)});
                obj.Handles.CurrentEdition.LineB = plot([XData(1) XData(1)],YData,'k','LineWidth',3,'Parent',src.Parent,'ButtonDownFcn',@(~,~)obj.DragLineB);
                obj.Handles.CurrentEdition.LineE = plot([XData(2) XData(2)],YData,'k','LineWidth',3,'Parent',src.Parent,'ButtonDownFcn',@(~,~)obj.DragLineE);
                obj.Handles.DeleteRange_Button.Enable = 'on';
                obj.Handles.DeleteRange_Button.Visible = 'on';
                if strcmpi(src.Parent.YLabel.String,'Grooming')
                    obj.Handles.ChangeRange_Button.Enable = 'on';
                    obj.Handles.ChangeRange_Button.Visible = 'on';
                end
            end
        end
        
        function PressKeyCB(obj,~,evt)
            switch evt.Key
                case 'return'
                    if obj.Editing
                        obj.RangeEditCB
                    end
                case 'space'
                    if isempty(gco) || gco ~= obj.Handles.UIElements.PlayButton
                        drawnow
                        obj.Play_CB;
                        drawnow
                    end
                case 'backspace'

                case 'delete'
                    if obj.Editing
                        obj.DeleteRangeCB
                    elseif ~isempty(obj.WindowSelected)
                        obj.RemoveExclusionRange_CB
                    end
                case 'rightarrow'
                    if obj.Editing
                        obj.EditNext
                    end
                case 'leftarrow'
                    if obj.Editing
                        obj.EditPrevious
                    end
                case 'pagedown'
                    if ~obj.Editing && ~obj.Dragging && ~isempty(obj.Reader)
                        obj.PlayNextRange;
                    end
                case 'pageup'
                    if ~obj.Editing && ~obj.Dragging && ~isempty(obj.Reader)
                        obj.PlayPreviousRange;
                    end
            end
        end
        
        
        function SaveSession(obj)
            if ~obj.Editing && ~obj.Dragging
                obj.Playing = false;
                BehaviourFile = [obj.Path  obj.Basename '_Behaviour.mat'];
                if exist(BehaviourFile,'file') == 2
                    Loaded = load(BehaviourFile);
                    ProcHist = [Loaded.Parameters.ProcessingHistory; {datetime,{getenv('username')},{mfilename}}];
                    delete(BehaviourFile)
                else
                    ProcHist = table(datetime,{getenv('username')},{mfilename},'VariableNames',{'Date','User','Version'});
                end
                
                Behaviour.ExclusionRanges = obj.ExclusionRanges;
                Behaviour.Parameters = obj.Parameters;
                Behaviour.Parameters.CrossChecked = true; % To allow for legacy extractions to go through a final iteration before using for plotting
                Behaviour.Parameters.DetectionToPlot = obj.Detection.ToPlot;
                Behaviour.Parameters.MeasurementsToPlot = obj.Measurements.ToPlot;
                Behaviour.Parameters.ProcessingHistory = ProcHist;
                for DTP = 1 : numel(obj.Detection.ToPlot)
                    DataDTP = [];
                    if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DTP}))
                        DataDTP = obj.Detection.Data.(obj.Detection.ToPlot{DTP});
                        DataDTP = DataDTP(~isnan(DataDTP(:,1)),:);
                        if size(DataDTP,1)>1,
                            [~,IndxSort] = sort(DataDTP);
                            DataDTP = DataDTP(IndxSort,:);
                            
                            IndxRmv = round(1000*DataDTP);
                            Break = false;
                            if numel(IndxRmv(:,1))>1
                                while ~Break
                                    Break = true;
                                    Reloop = false;
                                    % Loop through the ranges
                                    for R = 1 : numel(IndxRmv(:,1))
                                        for S = 1 : numel(IndxRmv(:,1))
                                            if S~=R
                                                if ~Reloop
                                                    % Find intersections
                                                    Intrsct = intersect(IndxRmv(R,1):IndxRmv(R,2),IndxRmv(S,1):IndxRmv(S,2));
                                                    if ~isempty(Intrsct)
                                                        % Extend ranges
                                                        Min = min([IndxRmv(R,1) IndxRmv(S,1)]);
                                                        IndxRmv(R,1) = Min;
                                                        IndxRmv(S,1) = Min;
                                                        Max = max([IndxRmv(R,2) IndxRmv(S,2)]);
                                                        IndxRmv(R,2) = Max;
                                                        IndxRmv(S,2) = Max;
                                                        Break = false;
                                                        IndxRmv = unique(IndxRmv,'rows');
                                                        Reloop = true;
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            DataDTP = IndxRmv/1000;
                        end
                    end
                    Behaviour.(obj.Detection.ToPlot{DTP}) = DataDTP;
                end
                
                save(BehaviourFile,'-struct','Behaviour')
            end
        end
        
        function AddExclusionRange(obj)
            
            obj.Handles.AddExclusionRange_Button.Callback = [];
            % Create hidden axes for range drawing
            HiddenAxes = axes('Position',[0.55 0.1 0.425 0.84],'Color','none','Visible','off','XColor','none','YColor','none');
            linkaxes([obj.Handles.DetectionAxes(1) HiddenAxes],'x')
            pause(0.01)
            RangeRectangle = drawrectangle(HiddenAxes);
            
            
            Range = sort([RangeRectangle.Position(1) RangeRectangle.Position(1)+RangeRectangle.Position(3)]);
            delete(HiddenAxes)
            obj.ExclusionRanges = [obj.ExclusionRanges;Range];
            [~,IndxSort] = sort(obj.ExclusionRanges(:,1));
            obj.ExclusionRanges = obj.ExclusionRanges(IndxSort,:);
            
            IndxRmv = round(1000*obj.ExclusionRanges);
            Break = false;
            if numel(IndxRmv(:,1))>1
                while ~Break
                    Break = true;
                    Reloop = false;
                    % Loop through the ranges
                    for R = 1 : numel(IndxRmv(:,1))
                        for S = 1 : numel(IndxRmv(:,1))
                            if S~=R
                                if ~Reloop
                                    % Find intersections
                                    Intrsct = intersect(IndxRmv(R,1):IndxRmv(R,2),IndxRmv(S,1):IndxRmv(S,2));
                                    if ~isempty(Intrsct)
                                        % Extend ranges
                                        Min = min([IndxRmv(R,1) IndxRmv(S,1)]);
                                        IndxRmv(R,1) = Min;
                                        IndxRmv(S,1) = Min;
                                        Max = max([IndxRmv(R,2) IndxRmv(S,2)]);
                                        IndxRmv(R,2) = Max;
                                        IndxRmv(S,2) = Max;
                                        Break = false;
                                        IndxRmv = unique(IndxRmv,'rows');
                                        Reloop = true;
                                    end
                                end
                            end
                        end
                    end
                end
            end
            obj.ExclusionRanges = IndxRmv/1000;

            Subs = [obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes];
            for S = 1 : numel(Subs)
                delete(obj.Handles.FillRemovedWindows{S}(:))
                if ~isempty(obj.ExclusionRanges)
                    obj.Handles.FillRemovedWindows{S} = arrayfun(@(x) fill([obj.ExclusionRanges(x,1) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,1)], [Subs(S).YLim(1) * [1 1]  Subs(S).YLim(2) * [1 1]],[0.85 0.9 0.85],'FaceAlpha',0.5,'EdgeColor','none','Parent',Subs(S),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.ExclusionRanges(:,1)));
                    uistack(obj.Handles.FillRemovedWindows{S},'bottom')
                end
            end
            
            obj.Handles.AddExclusionRange_Button.Callback = {@(~,~)obj.AddExclusionRange};
        end
        
        function SelectWindow(obj,src,~)
            Subs = [obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes];
            if obj.WindowSelected == str2double(src.Tag)
                obj.WindowSelected = [];
                
                [~,IndxSort] = sort(obj.ExclusionRanges(:,1));
                obj.ExclusionRanges = obj.ExclusionRanges(IndxSort,:);
                
                IndxRmv = round(1000*obj.ExclusionRanges);
                Break = false;
                if numel(IndxRmv(:,1))>1
                    while ~Break
                        Break = true;
                        Reloop = false;
                        % Loop through the ranges
                        for R = 1 : numel(IndxRmv(:,1))
                            for S = 1 : numel(IndxRmv(:,1))
                                if S~=R
                                    if ~Reloop
                                        % Find intersections
                                        Intrsct = intersect(IndxRmv(R,1):IndxRmv(R,2),IndxRmv(S,1):IndxRmv(S,2));
                                        if ~isempty(Intrsct)
                                            % Extend ranges
                                            Min = min([IndxRmv(R,1) IndxRmv(S,1)]);
                                            IndxRmv(R,1) = Min;
                                            IndxRmv(S,1) = Min;
                                            Max = max([IndxRmv(R,2) IndxRmv(S,2)]);
                                            IndxRmv(R,2) = Max;
                                            IndxRmv(S,2) = Max;
                                            Break = false;
                                            IndxRmv = unique(IndxRmv,'rows');
                                            Reloop = true;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                obj.ExclusionRanges = IndxRmv/1000;
                
                for S = 1 : numel(Subs)
                    delete(obj.Handles.FillRemovedWindows{S}(:))
                    delete(obj.Handles.LineStartRemovedWindows{S})
                    delete(obj.Handles.LineEndRemovedWindows{S})
                    if ~isempty(obj.ExclusionRanges)
                        obj.Handles.FillRemovedWindows{S} = arrayfun(@(x) fill([obj.ExclusionRanges(x,1) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,1)], [Subs(S).YLim(1) * [1 1]  Subs(S).YLim(2) * [1 1]],[0.85 0.9 0.85],'FaceAlpha',0.5,'EdgeColor','none','Parent',Subs(S),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.ExclusionRanges(:,1)));
                        uistack(obj.Handles.FillRemovedWindows{S},'bottom')
                    end
                end
                obj.Handles.AddExclusionRange_Button.Callback = {@(~,~)obj.AddExclusionRange};
                obj.Handles.AddExclusionRange_Button.String = 'Add exclusion range';
            else
                obj.WindowSelected = str2double(src.Tag);
                XData = src.Vertices([1 2],1);
                Colors = repmat({[0.85 0.85 0.9]},numel(obj.ExclusionRanges(:,1)),1);
                LineColors = repmat({[1 1 1]},numel(obj.ExclusionRanges(:,1)),1);
                Colors(obj.WindowSelected,:) = {[0.5 0.85 0.94]};
                LineColors(obj.WindowSelected,:) = {[0 0 0]};
                for S = 1 : numel(Subs)
                    set(obj.Handles.FillRemovedWindows{S},{'FaceColor'},Colors)
                    set(obj.Handles.FillRemovedWindows{S},{'EdgeColor'},LineColors)
                    delete(obj.Handles.LineStartRemovedWindows{S})
                    delete(obj.Handles.LineEndRemovedWindows{S})
                    obj.Handles.LineStartRemovedWindows{S} = plot(XData(1)*[1 1],Subs(S).YLim,'k','LineWidth',3,'Parent',Subs(S),'ButtonDownFcn',{@(src,evt)obj.DragLineWRS(src,evt)},'Tag',src.Tag);
                    obj.Handles.LineEndRemovedWindows{S} = plot(XData(2)*[1 1],Subs(S).YLim,'k','LineWidth',3,'Parent',Subs(S),'ButtonDownFcn',{@(src,evt)obj.DragLineWRE(src,evt)},'Tag',src.Tag);
                end
                obj.Handles.AddExclusionRange_Button.Callback = {@(~,~)obj.RemoveExclusionRange_CB};
                obj.Handles.AddExclusionRange_Button.String = 'Remove exclusion range';
                drawnow
            end
        end
        
        function RemoveExclusionRange_CB(obj)
            obj.ExclusionRanges(obj.WindowSelected,:) = [];
            Subs = [obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes];
            for S = 1 : numel(Subs)
                delete(obj.Handles.FillRemovedWindows{S}(:))
                delete(obj.Handles.LineStartRemovedWindows{S})
                delete(obj.Handles.LineEndRemovedWindows{S})
                if ~isempty(obj.ExclusionRanges)
                    obj.Handles.FillRemovedWindows{S} = arrayfun(@(x) fill([obj.ExclusionRanges(x,1) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,2) obj.ExclusionRanges(x,1)], [Subs(S).YLim(1) * [1 1]  Subs(S).YLim(2) * [1 1]],[0.85 0.9 0.85],'FaceAlpha',0.5,'EdgeColor','none','Parent',Subs(S),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:numel(obj.ExclusionRanges(:,1)));
                    uistack(obj.Handles.FillRemovedWindows{S},'bottom')
                end
            end
            obj.Handles.AddExclusionRange_Button.Callback = {@(~,~)obj.AddExclusionRange};
            obj.Handles.AddExclusionRange_Button.String = 'Add exclusion range';
            obj.WindowSelected = [];
        end
        
        function DragLineWRS(obj,src,~)
            if ~obj.Dragging
                obj.Playing = false;
                obj.Dragging = true;
                obj.CurrentWindowLine = src;
                obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingLineWRS;
                obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.DragLineWRS;
            else
                obj.Dragging = false;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
            end
        end
        
        function MovingLineWRS(obj)
            CurrentX = obj.CurrentWindowLine.Parent.CurrentPoint(1);
            Subs = [obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes];
            for S = 1 : numel(Subs)
                obj.Handles.FillRemovedWindows{S}(str2double(obj.CurrentWindowLine.Tag)).Vertices([1 4],1) = CurrentX;
                obj.Handles.LineStartRemovedWindows{S}.XData = CurrentX * [1 1];
            end
            if ~obj.Refractory
                obj.Refractory = true;
                obj.ExclusionRanges(str2double(obj.CurrentWindowLine.Tag),1) = CurrentX;
                obj.CurrentTime = CurrentX;
                obj.PlayMovies;
                obj.Refractory = false;
            end
        end
        
        function DragLineWRE(obj,src,~)
            if ~obj.Dragging
                obj.Playing = false;
                obj.Dragging = true;
                obj.CurrentWindowLine = src;
                obj.Handles.MainFigure.WindowButtonMotionFcn = @(~,~)obj.MovingLineWRE;
                obj.Handles.MainFigure.WindowButtonUpFcn = @(~,~)obj.DragLineWRE;
            else
                obj.Dragging = false;
                obj.Handles.MainFigure.WindowButtonMotionFcn = [];
                obj.Handles.MainFigure.WindowButtonUpFcn = [];
            end
        end
        
        function MovingLineWRE(obj)
            CurrentX = obj.CurrentWindowLine.Parent.CurrentPoint(1);
            Subs = [obj.Handles.DetectionAxes obj.Handles.MeasurementsAxes];
            for S = 1 : numel(Subs)
                obj.Handles.FillRemovedWindows{S}(str2double(obj.CurrentWindowLine.Tag)).Vertices([2 3],1) = CurrentX;
                obj.Handles.LineEndRemovedWindows{S}.XData = CurrentX * [1 1];
            end
            if ~obj.Refractory
                obj.Refractory = true;
                obj.ExclusionRanges(str2double(obj.CurrentWindowLine.Tag),2) = CurrentX;
                obj.CurrentTime = CurrentX;
                obj.PlayMovies;
                obj.Refractory = false;
            end
        end
   
        function UpdateLogical(obj)
            BaseArray = false(size(obj.Times));
            for DT = 1 : numel(obj.Detection.ToPlot)
                obj.Detection.Logical.(obj.Detection.ToPlot{DT}) = BaseArray;
                if ~isempty(obj.Detection.Data.(obj.Detection.ToPlot{DT}))
                    for Ev = 1 : numel(obj.Detection.Data.(obj.Detection.ToPlot{DT})(:,1))
                        Indx = FindInInterval(obj.Times,obj.Detection.Data.(obj.Detection.ToPlot{DT})(Ev,:));
                        obj.Detection.Logical.(obj.Detection.ToPlot{DT})(Indx(1):Indx(2)) = true;
                    end
                end
            end
        end
        
        function Replot(obj,Behav)
            delete(obj.Handles.DetectionRanges.(Behav))
            Behav_Axes = find(arrayfun(@(x) strcmpi(obj.Handles.DetectionAxes(x).YLabel.String,Behav),1:numel(obj.Handles.DetectionAxes)));
            DC = repmat(DefColors,3,1);
            obj.Handles.DetectionRanges.(Behav) = arrayfun(@(x) fill(obj.Detection.Data.(Behav)(x,[1 2 2 1]),[0 0 1 1],DC(Behav_Axes,:),'EdgeColor',DC(Behav_Axes,:),'LineWidth',1,'Parent',obj.Handles.DetectionAxes(Behav_Axes),'ButtonDownFcn',{@(src,evt)obj.RangeEditCB(src,evt)},'Tag',Behav,'UserData',num2str(x)),1:size(obj.Detection.Data.(Behav),1));
        end
        
    end
end