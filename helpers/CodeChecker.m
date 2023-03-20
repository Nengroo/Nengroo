classdef CodeChecker < handle
    %CODECHECKER - Class for evaluating code from ChatGPT
    %   CodeChecker is a class that can extract code from ChatGPT
    %   responses, run the code with a unit testing framework, and return
    %   the test results in a format for display in a chat window. Each
    %   input message from ChatGPT gets its own test folder to hold the
    %   generated code and artifacts like test results and images
    %
    %   Example:
    %
    %       % Get a message from ChatGPT
    %       myBot = chatGPT();
    %       response = chat(myBot,"Create a bar plot in MATLAB.");
    %
    %       % Create object
    %       checker = CodeChecker(response);
    %
    %       % Check code for validity and display test report
    %       report = runChecks(checker);
    %       disp(report)

    properties (SetAccess=private)
        ChatResponse % ChatGPT response that may have code 
        OutputFolder % Full path with test results
        Results % Table with code results
        Timestamp % Unique string with current time to use for names
    end

    methods
        %% Constructor
        function obj = CodeChecker(inputStr,pathStr)
            %CODECHECKER Constructs an instance of this class
            %    checker = CodeChecker(message) creates an instance
            %    of the CodeChecker class given a response from
            %    ChatGPT in the string "message".
            arguments
                inputStr string {mustBeTextScalar}
                pathStr string {mustBeTextScalar} = "";
            end
            obj.ChatResponse = inputStr;
            if pathStr == ""
                s = dir;
                pathStr = s(1).folder;
            end
            % Construct a unique output folder name using a timstamp
            obj.Timestamp = string(datetime('now','Format','yyyy-MM-dd''T''HH-mm-SS'));
            obj.OutputFolder = fullfile(pathStr,"contents","GeneratedCode","Test-" + obj.Timestamp);

            % Empty Results table
            obj.Results = [];
        end
    end
    methods (Access=public)
        function [report,errorMessages] = runChecks(obj)
            % RUNCHECKS - Run generated code and check for errors
            %   report = runChecks(obj) will use the unit test defined
            %   ChatGPTUnitTest to run each piece of generated code. The
            %   output is a string to be displayed in the Chat window.
            % 
            %       NOTE: This function does not check generated code 
            %       for correctness, just validity
            %
            %   [report,errorMessagess] = rubChecks(obj) also returns the 
            %   detected errors across all checks
    
            % make the output folder and add it to the path
            mkdir(obj.OutputFolder)
            addpath(obj.OutputFolder)
    
            % save code files and get their names for testing;
            saveCodeFiles(obj);
    
            % Run all test files
            runCodeFiles(obj);
    
            % Return report string
            [report,errorMessages] = joinTestResults(obj);
        end
    end

    methods(Access=private)
        function saveCodeFiles(obj)
            % SAVECODEFILES Saves M-files for testing
            %    saveCodeFiles(obj) will parse the ChatResponse propety for
            %    code blocks and save them to separate M-files with unique
            %    names in the OutputFolder property location

            % Extract code blocks
            [startTag,endTag] = TextHelper.codeBlockPattern();
            codeBlocks = extractBetween(obj.ChatResponse,startTag,endTag);

            % Create Results table
            obj.Results = table('Size',[length(codeBlocks) 5],'VariableTypes',["string","string","string","logical","cell"], ...
                'VariableNames',["ScriptName","ScriptContents","ScriptOutput","IsError","Figures"]);
            obj.Results.ScriptContents = codeBlocks;

            % Save code blocks to M-files
            for i = 1:height(obj.Results)
                % Open file with the function name or a generic test name.
                obj.Results.ScriptName(i) = "Test" + i + "_" + replace(obj.Timestamp,"-","_");
                fid = fopen(fullfile(obj.OutputFolder,obj.Results.ScriptName(i) + ".m"),"w");                

                % Add the code to the file
                fprintf(fid,"%s",obj.Results.ScriptContents(i));
                fclose(fid);
            end
        end

        function runCodeFiles(obj)
            % RUNCODEFILES - Tries to run all the generated scripts and
            % captures outputs/figures

            % Before tests, hide the handles for currently visible figures.
            % This ensures they don't get captured
            previousFigs = findobj('Type','figure');
            for i = 1:length(previousFigs)
                previousFigs(i).HandleVisibility = 'off';
            end

            % Iterate through scripts
            for i = 1:height(obj.Results)

                % Run the code and capture any output 
                try 
                    obj.Results.ScriptOutput(i) = evalc(obj.Results.ScriptName(i));
                catch ME
                    obj.Results.IsError(i) = true;
                    obj.Results.ScriptOutput(i) = TextHelper.shortErrorReport(ME);
                end                    

                % Save figures
                figs = findobj('Type','figure');
                figNames = strings(size(figs));
                for j = 1:length(figs)
                    figNames(j) = obj.Results.ScriptName(i) + "_Figure" + j + ".png";
                    saveas(figs(j),figNames(j));                    
                end            
                close all
                obj.Results.Figures{i} = figNames;
            end

            % Unhide the original figures
            for i = 1:length(previousFigs)
                previousFigs(i).HandleVisibility = 'on';
            end
        end

        function [testReport,errorMessages] = joinTestResults(obj)
            %  JOINTESTRESULTS Assemble test report from multiple tests
            %
            %  report = joinTestResults(results) assembles a report given
            %  the results of a test suite. The report will show error
            %  messages, command window output, or images from captured
            %  figures
            %
            %  [report,errorMessages] = joinTestResults(results) also
            %  returns a cellstr array with the error messages

            % Loop through results
            testReport = '';
            for i = 1:height(obj.Results)

                % Start the report with the script name
                testReport = [testReport sprintf('%s Test: %s %s\n\n',repelem('-',15), ...
                    obj.Results.ScriptName(i),repelem('-',15))]; %#ok<AGROW>

                % Add code
                testReport = [testReport sprintf('%%%% Code: \n%s\n\n', ...
                    obj.Results.ScriptContents(i))]; %#ok<AGROW>

                % Add output
                testReport = [testReport sprintf('%%%% Output: \n%s\n\n', ...
                    obj.Results.ScriptOutput(i))]; %#ok<AGROW>

                % Handle figures
                figNames = obj.Results.Figures{i};
                for j = 1:length(figNames)

                    % Move image to output filder
                    movefile(figNames(j),obj.OutputFolder);

                    % Get the relative path of the image. Assumes that the HTML
                    % file is at the same level as the "GeneratedCode" folder
                    folders = split(obj.OutputFolder,filesep);
                    relativePath = fullfile(folders(end-1),folders(end),figNames(j));
                    relativePath = replace(relativePath,'\','/');
    
                    % Assemble the html code for displaying the image
                    testReport = [testReport sprintf('Image saved to: %s\n\n<img src="%s" class="ml-figure"/>\n\n', ...
                        fullfile(folders(end-2),relativePath),relativePath)]; %#ok<AGROW>
                end
            end

            errorMessages = obj.Results.ScriptOutput(obj.Results.IsError);

            % Remove trailing newlines
            testReport = strip(testReport,"right");   
        end
    end
end