function rval = workerbee(im, SVM_beige, SVM_blue, SVM_brown)
try
    cmap = containers.Map({'black', 'brown', 'red', 'orange', 'yellow', 'green', 'blue', 'violet', 'gray', 'white', 'gold'}, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1}); %#ok<CLARRSTR>
    tolmap = containers.Map({'gold', 'gray', 'purple', 'blue', 'green', 'red', 'brown'}, {'5%', '10%', '0.1%', '0.25%', '0.5%', '1%', '2%'}); %#ok<CLARRSTR>
    im1 = im(:, :, 1);
    im2= im(:, :, 2);
    im3= im(:, :, 3);
    BW3 = edge(imgaussfilt(im3, 3), 'canny', 0.1);
    BW2 = edge(imgaussfilt(im2, 3), 'canny', 0.1);
    BW1 = edge(imgaussfilt(im1, 3), 'canny', 0.1);
    bw12 = imadd(BW1, BW2);
    BW = imadd(bw12, double(BW3));
    % emphasizing horizontal lines
    BW = imopen(BW, [1 1 1]);
    % getting hough lines
    [H,T,R] = hough(BW, 'Theta',[-90:-80 80:89]);
    P = houghpeaks(H, 50, 'Threshold', ceil(0.33*max(H(:))), 'theta',[-90:-80 80:89]);
    lines = houghlines(BW,T,R,P,'FillGap',15,'MinLength',30);
    lines = table2array(struct2table(lines));
    ll = size(lines);
    ll = ll(1);
    lines(:, 7) = zeros([ll 1]);
    % 1: pt1x 2: pt1y 3: pt2x 4: pt2y 5: cntrx 6: cntry 7: theta
    for i = 1:ll % add the theta information and the center information
        slope = (lines(i, 2) -lines(i, 4))./ (lines(i, 1)-lines(i, 3));
        lines(i, 7) = atand(slope);
        centers = round([lines(i, 1)+lines(i, 3) lines(i, 2)+lines(i, 4)]./2);
        lines(i, 5:6) = centers;
    end

    newlines = tooclose(lines); % de duplication
    size_newlines = size(newlines);
    if size_newlines(1) < 8 || size_newlines(1) > 15 % size checking
        rval = "1";
        return
    end
    newlines = sortrows(newlines, 6); % sort vertically
    lc = size(newlines);
    lc = lc(1);
    colors2 = containers.Map('KeyType', 'double', 'ValueType', 'any');
    % color extraction
    for l=1:lc-1
        colors2(l) = [];
        centersx = zeros([2 10]);
        centersy = zeros([2 10]);
        ang1 = (newlines(l, 7));
        ang2 = (newlines(l+1, 7));
        for m = 1:20 % this is the main part where the pixels are picked out
            centersx(1, m) = round(newlines(l, 5) + (m-10).*cosd(ang1));
            centersx(2, m) = round(newlines(l+1, 5) + (m-10).*cosd(ang2));
            centersy(1, m) = round(newlines(l, 6) + (m-10).*sind(ang1));
            centersy(2, m) = round(newlines(l+1, 6) + (m-10).*sind(ang2));
            [~, ~, c] = improfile(im, centersx(:, m) , centersy(:, m));
            s = size(c);
            colors2(l) = [colors2(l); reshape(c, [s(1) s(3) s(2)])];
        end
    end
    
    meds = [];
    for k=1:length(colors2.keys)
        colors2(k) = colors2(k)./255;
        meds = [meds; median(colors2(k))];
    end
    adj = zeros(length(colors2.keys)); % finding the distances between colors
    % the series with the lowest distance is the body of the resistor
    for k = cell2mat(colors2.keys)
        for l = cell2mat(colors2.keys)
            med1 = rgb2lab(meds(k, :));
            med2 = rgb2lab(meds(l, :));
            d_unscaled = med1 - med2;
            std1 = std(rgb2lab(colors2(k)));
            std2 = std(rgb2lab(colors2(l)));
            d1 = d_unscaled./std1;
            d2 = d_unscaled./std2;
            avg_n_dist = (d1 + d2)./2;
            adj(k, l) = norm(avg_n_dist);
        end
    end

    %g_or_l holds candidates for body sequences
    g_or_l = containers.Map('KeyType', 'double', 'ValueType', 'any');
    for series = [1 2]
        my_series = series;
        while my_series(end) +2<= length(colors2.keys)
            if (sm(adj, [my_series my_series(end) + 2]) < sm(adj, [my_series my_series(end) + 1]))
                my_series = [my_series my_series(end) + 2];
            else
                my_series = [my_series my_series(end) + 1];
            end
        end
        g_or_l(series) = my_series; % two candidate series are stored in g_or_l: which one is the body bands and which is the resistor bands?
    end

    % r_series is the resistor bands, b_series is the body bands
    if sm(adj, g_or_l(1)) < sm(adj, g_or_l(2)) && (length(setdiff(1:length(colors2.keys), g_or_l(1))) >= 4)
        r_series = setdiff(1:length(colors2.keys), g_or_l(1)); 
        b_series = g_or_l(1);
    else
        r_series = setdiff(1:length(colors2.keys), g_or_l(2));
        b_series = g_or_l(2);
    end

    m = zeros(1, 3);
    for k = b_series
        pre_m = meds(k, :);
        m = m+ rgb2hsv(imadjust(pre_m, [], [], 1/2.2));
    end
    m = m./length(b_series);

    if m(1) > 0.33 && m(1) < 0.75
        svm = SVM_blue;
    elseif m(3) > 0.6
        svm = SVM_beige;
    else
        svm = SVM_brown;
    end
    tgc = strings(1, length(r_series)); % tgc is the colors for the resistor bands
    clrs_cnt = 1;
    gmap = containers.Map('KeyType', 'double', 'ValueType', 'any');
    for k=r_series
        m = meds(k, :);
        my_med = imadjust(m, [], [], 1/2.2);
        [mycolor_pre, loss] = predict(svm, rgb2lab(my_med));
        mycolor = mycolor_pre{1, 1};
        tgc(clrs_cnt) = mycolor;
        if strcmp(mycolor, 'gold')
            B = sort(loss, 'descend');
            Max2 = svm.ClassNames(find(loss == B(2)));

            gmap(clrs_cnt) = Max2{1, 1};
        end
        clrs_cnt = clrs_cnt + 1;
    end

    % the next section determines which side the tolerance band is on
    % The pattern reader reads from beginning to end, so if the tolerance is at
    % the start the sequence will have to be flipped. The variable tol keeps
    % track of this; if tol==1 the tolerance band is at the start.
    if tgc(1) == "gold" && tgc(end) ~="gold"
        tol = 1;
    elseif tgc(end) == "gold" && tgc(1) ~="gold"
        tol = 0;
    elseif tgc(1) == "gray" && length(tgc) == 4
        tol = 1;
    elseif tgc(end) == "gray" && length(tgc) == 4
        tol = 0;
    elseif ~isKey(tolmap, tgc(1)) && isKey(tolmap, tgc(end))
        tol = 0;
    elseif isKey(tolmap, tgc(1)) && ~isKey(tolmap, tgc(end))
        tol = 1;
    elseif tgc(end-1) == "gray"
        tol = 1;
    elseif tgc(2) == "gray"
        tol = 0;
    elseif isKey(tolmap, tgc(1)) && isKey(tolmap, tgc(end))
        myendstats2 = myendstats(newlines, r_series, colors2.keys);
        ind = which_tol(myendstats2);
        if (ind == 1)
            tol = 1;
        else
            tol = 0;
        end
    end
    % end of tolerance finding
    % flip tgc (the colors) if tol == 1
    if tol
        tgc = flip(tgc);
    end

    % remove the occasional extra "band": a resistor with gold or gray
    % tolerance generally only has four bands, and any resistor that I am
    % designing my program to handle has no more than five bands.
    if (tgc(length(tgc)) == "gold" || tgc(length(tgc)) == "gray")
        cur_cnt = length(tgc) - 3;
    else
        cur_cnt = max(1, length(tgc)-4);
    end

    % display the resistance
    num = "";
    for el = tgc(cur_cnt:end)
        if strcmp(el, 'gold') && cur_cnt < length(tgc) -1
            if ~tol
                idx = cur_cnt;
            else
                idx = length(tgc)-cur_cnt+1;
            end
            tgc(cur_cnt) = cmap(convertCharsToStrings(gmap(idx)));
        elseif cur_cnt == length(tgc)
            tgc(cur_cnt) = tolmap(convertCharsToStrings(el));
        else
            tgc(cur_cnt) = cmap(convertCharsToStrings(el));
        end

        if cur_cnt == length(tgc)-1
            num = num + "e" + tgc(cur_cnt);
        elseif cur_cnt == length(tgc)
            tol = tgc(cur_cnt);
        else
            num = num + tgc(cur_cnt);
        end
        cur_cnt = cur_cnt + 1;
    end
    dbl = str2double(num);
    if (dbl >= 1000000)
        append = " M?? ??";
        dbl = dbl./1000000;
    elseif (dbl >= 1000)
        append = " k?? ??";
        dbl = dbl./1000;
    else
        append = " ?? ??";
    end
    num = "Resistance: " + dbl + append + tol;
    rval = num;
catch % if anything went wrong return the error code and ignore it
    rval = "1";
    return
end
end
