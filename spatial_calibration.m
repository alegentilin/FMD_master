function [pixeltocm] = spatial_calibration(video_file,n_frame)

pixeltocm = 0;
global calibration;
global originalImage;


% Check that user has the Image Processing Toolbox installed.
clc;    % Clear the command window.
close all;  % Close all figures (except those of imtool.)
workspace;  % Make sure the workspace panel is showing.
format long g;
format compact;
fontSize = 20;

hasIPT = license('test', 'image_toolbox');
if ~hasIPT
	% User does not have the toolbox installed.
	message = sprintf('Sorry, but you do not seem to have the Image Processing Toolbox.\nDo you want to try to continue anyway?');
	reply = questdlg(message, 'Toolbox missing', 'Yes', 'No', 'Yes');
	if strcmpi(reply, 'No')
		% User said No, so exit.
		return;
	end
end


% Read in the chosen standard MATLAB demo image. --> read first frame
originalImage = read(video_file,n_frame);

% Get the dimensions of the image.
[rows, columns, numberOfColorBands] = size(originalImage);

figure;
imshow(originalImage); title('Raw Image');

button = 1; % Allow it to enter loop.

while button ~= 4
	if button > 1
		% Let them choose the task, once they have calibrated.
		button = menu('Select a task', 'Re-Calibrate', 'Proceed Analyzing Video');
	end
	switch button
		case 1
			 [pixeltocm] = Calibrate(calibration);
            
			% If they get to here, they clicked properly
			% Change to something else so it will ask them
			% for the task on the next time through the loop.
			button = 99;
		otherwise
			%close(figure); 
            close all;
			break;
	end
end

end

%=====================================================================
function [value] = Calibrate (calibration)
global lastDrawnHandle;

 
try
	%success = false;
	instructions = sprintf('Spatial Calibration \nLeft click to anchor first point.\nRight-click or double-click to anchor second point');
	msgboxw(instructions);

 	[cx, cy, rgbValues, xi,yi] = improfile(1000);


    
	% rgbValues is 1000x1x3.  Call Squeeze to get rid of the singleton dimension and make it 1000x3.
	rgbValues = squeeze(rgbValues);
	distanceInPixels = sqrt( (xi(2)-xi(1)).^2 + (yi(2)-yi(1)).^2);
	if length(xi) < 2
		return;
	end
	% Plot the line.
	hold on;
	lastDrawnHandle = plot(xi, yi, 'y-', 'LineWidth', 4);

	% Ask the user for the real-world distance.
	userPrompt = {'Enter real world units (e.g. mm):','Enter distance in those units:'};
	dialogTitle = 'Specify calibration information';
	numberOfLines = 1;
	def = {'cm', '1'};
	answer = inputdlg(userPrompt, dialogTitle, numberOfLines, def);
	if isempty(answer)
		return;
	end
	calibration.units = answer{1};
	calibration.distanceInPixels = distanceInPixels;
	calibration.distanceInUnits = str2double(answer{2});
	calibration.distancePerPixel = calibration.distanceInUnits / distanceInPixels;
    value = distanceInPixels / calibration.distanceInUnits;
	

catch ME
	errorMessage = sprintf('Error in function Calibrate().\nDid you first left click and then right click?\n\nError Message:\n%s', ME.message);
	fprintf(1, '%s\n', errorMessage);
	WarnUser(errorMessage);
end

return;	% from Calibrate()
end
%=====================================================================
function msgboxw(message)
	uiwait(msgbox(message));
end
%=====================================================================
function WarnUser(message)
	uiwait(msgbox(message));
end

