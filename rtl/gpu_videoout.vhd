library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pGPU.all;

entity gpu_videoout is
   port 
   (
      clk1x                      : in  std_logic;
      clk2x                      : in  std_logic;
      ce                         : in  std_logic;
      reset                      : in  std_logic;
      softReset                  : in  std_logic;
            
      videoout_settings          : in  tvideoout_settings;
      videoout_reports           : out tvideoout_reports;
            
      videoout_on                : in  std_logic;
            
      debugmodeOn                : in  std_logic;
         
      fpscountOn                 : in  std_logic;
      fpscountBCD                : in  unsigned(7 downto 0);     
   
      Gun1CrosshairOn            : in  std_logic;
      Gun1X                      : in  unsigned(7 downto 0);
      Gun1Y_scanlines            : in  unsigned(8 downto 0);
   
      Gun2CrosshairOn            : in  std_logic;
      Gun2X                      : in  unsigned(7 downto 0);
      Gun2Y_scanlines            : in  unsigned(8 downto 0);   
            
      cdSlow                     : in  std_logic;
            
      errorOn                    : in  std_logic;
      errorEna                   : in  std_logic;
      errorCode                  : in  unsigned(3 downto 0); 
         
      requestVRAMEnable          : out std_logic := '0';
      requestVRAMXPos            : out unsigned(9 downto 0);
      requestVRAMYPos            : out unsigned(8 downto 0);
      requestVRAMSize            : out unsigned(10 downto 0);
      requestVRAMIdle            : in  std_logic;
      requestVRAMDone            : in  std_logic;
            
      vram_DOUT                  : in  std_logic_vector(63 downto 0);
      vram_DOUT_READY            : in  std_logic;
            
      video_ce                   : buffer std_logic := '0';
      video_r                    : out std_logic_vector(7 downto 0);
      video_g                    : out std_logic_vector(7 downto 0);
      video_b                    : out std_logic_vector(7 downto 0);
      video_hblank               : out std_logic := '1';
      video_hsync                : out std_logic := '0';
      
      videoout_ss_in             : in  tvideoout_ss;
      videoout_ss_out            : out tvideoout_ss
   );
end entity;

architecture arch of gpu_videoout is
    
   signal DisplayOffsetX      : unsigned( 9 downto 0) := (others => '0'); 
   signal DisplayOffsetY      : unsigned( 8 downto 0) := (others => '0'); 
    
   -- data fetch
   signal videoout_request    : tvideoout_request;
   signal videoout_pixelRead  : std_logic_vector(15 downto 0);
   
   type tState is
   (
      WAITNEWLINE,
      REQUEST,
      WAITREAD
   );
   signal state : tState := WAITNEWLINE;
   
   signal reqPosX             : unsigned(9 downto 0) := (others => '0');
   signal reqPosY             : unsigned(8 downto 0) := (others => '0');
   signal reqSize             : unsigned(10 downto 0) := (others => '0');
   signal lineAct             : unsigned(8 downto 0) := (others => '0');
   signal fillAddr            : unsigned(8 downto 0) := (others => '0');
   signal store               : std_logic := '0';
   
   -- overlay
   signal overlay_data        : std_logic_vector(23 downto 0);
   signal overlay_ena         : std_logic;
   
   signal fpstext             : unsigned(15 downto 0);
   signal overlay_fps_data    : std_logic_vector(23 downto 0);
   signal overlay_fps_ena     : std_logic;
   
   signal overlay_cd_data     : std_logic_vector(23 downto 0);
   signal overlay_cd_ena      : std_logic;
   
   signal errortext           : unsigned(7 downto 0);
   signal overlay_error_data  : std_logic_vector(23 downto 0);
   signal overlay_error_ena   : std_logic;
   
   signal debugtextDbg        : unsigned(23 downto 0);
   signal debugtextDbg_data   : std_logic_vector(23 downto 0);
   signal debugtextDbg_ena    : std_logic;

   signal overlay_Gun1_ena    : std_logic;
   signal overlay_Gun2_ena    : std_logic;

   signal Gun1X_screen        : integer range 0 to 1023;
   signal Gun2X_screen        : integer range 0 to 1023;

   signal Gun1Y_screen        : unsigned(9 downto 0);
   signal Gun2Y_screen        : unsigned(9 downto 0);
   
begin 
  
   igpu_videoout_sync : entity work.gpu_videoout_sync
   port map
   (
      clk1x                   => clk1x,
      clk2x                   => clk2x,
      ce                      => ce,   
      reset                   => reset,
      softReset               => softReset,
               
      videoout_settings       => videoout_settings,
      videoout_reports        => videoout_reports,                 
                                                
      videoout_on             => videoout_on,            
                                   
      debugmodeOn             => debugmodeOn,            
                             
      fpscountOn              => fpscountOn,             
      fpscountBCD             => fpscountBCD,            
                    
      Gun1CrosshairOn         => Gun1CrosshairOn,        
      Gun1X                   => Gun1X,                  
      Gun1Y_scanlines         => Gun1Y_scanlines,        
                        
      Gun2CrosshairOn         => Gun2CrosshairOn,        
      Gun2X                   => Gun2X,                  
      Gun2Y_scanlines         => Gun2Y_scanlines,          
                     
      cdSlow                  => cdSlow,                 
                  
      errorOn                 => errorOn,                
      errorEna                => errorEna,               
      errorCode               => errorCode,              
                                
      videoout_request        => videoout_request,   
      videoout_pixelRead      => videoout_pixelRead,   

      overlay_data            => overlay_data,
      overlay_ena             => overlay_ena,       
                         
      vram_DOUT               => vram_DOUT,              
      vram_DOUT_READY         => vram_DOUT_READY,        
                   
      video_ce                => video_ce,               
      video_r                 => video_r,                
      video_g                 => video_g,                
      video_b                 => video_b,                
      video_hblank            => video_hblank,           
      video_hsync             => video_hsync,
      
      videoout_ss_in          => videoout_ss_in,
      videoout_ss_out         => videoout_ss_out      
   );
   
   -- vram reading
   requestVRAMEnable <= '1'     when (state = REQUEST and requestVRAMIdle = '1') else '0';
   requestVRAMXPos   <= reqPosX when (state = REQUEST and requestVRAMIdle = '1') else (others => '0');
   requestVRAMYPos   <= reqPosY when (state = REQUEST and requestVRAMIdle = '1') else (others => '0');
   requestVRAMSize   <= reqSize when (state = REQUEST and requestVRAMIdle = '1') else (others => '0');
   
   DisplayOffsetX <= videoout_settings.vramRange(9 downto 0);
   DisplayOffsetY <= videoout_settings.vramRange(18 downto 10);
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         
         if (reset = '1') then
         
            state   <= WAITNEWLINE;
            lineAct <= (others => '0');
         
         elsif (ce = '1') then
         
            case (state) is
            
               when WAITNEWLINE =>
                  if (videoout_on = '1' and videoout_request.lineInNext /= lineAct and videoout_request.fetch = '1' and videoout_settings.GPUSTAT_DisplayDisable = '0') then
                     state     <= REQUEST;
                     lineAct   <= videoout_request.lineInNext;
                     reqPosX   <= DisplayOffsetX;
                     reqPosY   <= videoout_request.lineInNext + DisplayOffsetY;
                     fillAddr  <= videoout_request.lineInNext(0) & x"00";
                     if (videoout_settings.GPUSTAT_VerRes = '1') then
                        fillAddr(8) <= videoout_request.lineInNext(1);
                     end if;
                     if (videoout_settings.GPUSTAT_ColorDepth24 = '1') then
                        reqSize <= resize(videoout_settings.DisplayWidth, 11) + resize(videoout_settings.DisplayWidth(9 downto 1), 11);
                     else
                        reqSize <= '0' & videoout_settings.DisplayWidth;
                     end if;
                  end if;

               when REQUEST =>
                  if (requestVRAMIdle = '1') then
                     state <= WAITREAD;
                     store <= '1';
                  end if;
                  
               when WAITREAD =>
                  if (vram_DOUT_READY = '1') then
                     fillAddr <= fillAddr + 1;
                  end if;
                  if (requestVRAMDone = '1') then
                     state <= WAITNEWLINE; 
                     store <= '0';
                  end if;
            
            end case;
         
         end if;
         
      end if;
   end process; 
   
   ilineram: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 9,
      data_width_a  => 64,
      addr_width_b  => 11,
      data_width_b  => 16
   )
   port map
   (
      clock       => clk2x,
      
      address_a   => std_logic_vector(fillAddr),
      data_a      => vram_DOUT,
      wren_a      => (vram_DOUT_READY and store),
      
      address_b   => std_logic_vector(videoout_request.readAddr),
      data_b      => x"0000",
      wren_b      => '0',
      q_b         => videoout_pixelRead
   );
  
  
   -- overlays
   fpstext( 7 downto 0) <= resize(fpscountBCD(3 downto 0), 8) + 16#30#;
   fpstext(15 downto 8) <= resize(fpscountBCD(7 downto 4), 8) + 16#30#;
   
   ioverlayFPS : entity work.gpu_overlay
   generic map
   (
      COLS                   => 2,
      BACKGROUNDON           => '1',
      RGB_BACK               => x"FFFFFF",
      RGB_FRONT              => x"0000FF",
      OFFSETX                => 4,
      OFFSETY                => 4
   )
   port map
   (
      clk                    => clk2x,
      ce                     => video_ce,
      ena                    => fpscountOn,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => overlay_fps_data,
      o_pixel_out_ena        => overlay_fps_ena,
      textstring             => fpstext
   );
   
   ioverlayCD : entity work.gpu_overlay
   generic map
   (
      COLS                   => 2,
      BACKGROUNDON           => '1',
      RGB_BACK               => x"FFFFFF",
      RGB_FRONT              => x"0000FF",
      OFFSETX                => 4,
      OFFSETY                => 24
   )
   port map
   (
      clk                    => clk2x,
      ce                     => video_ce,
      ena                    => cdSlow,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => overlay_cd_data,
      o_pixel_out_ena        => overlay_cd_ena,
      textstring             => x"4344"
   );
   
   errortext <= resize(errorCode, 8) + 16#30# when (errorCode < 10) else resize(errorCode, 8) + 16#37#;
   ioverlayError : entity work.gpu_overlay
   generic map
   (
      COLS                   => 2,
      BACKGROUNDON           => '1',
      RGB_BACK               => x"FFFFFF",
      RGB_FRONT              => x"0000FF",
      OFFSETX                => 4,
      OFFSETY                => 44
   )
   port map
   (
      clk                    => clk2x,
      ce                     => video_ce,
      ena                    => errorOn and errorEna,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => overlay_error_data,
      o_pixel_out_ena        => overlay_error_ena,
      textstring             => x"45" & errortext
   );   
   
   idebugtext_dbg : entity work.gpu_overlay
   generic map
   (
      COLS                   => 3,
      BACKGROUNDON           => '1',
      RGB_BACK               => x"FFFFFF",
      RGB_FRONT              => x"0000FF",
      OFFSETX                => 30,
      OFFSETY                => 4
   )
   port map
   (
      clk                    => clk2x,
      ce                     => video_ce,
      ena                    => debugmodeOn,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => debugtextDbg_data,
      o_pixel_out_ena        => debugtextDbg_ena,
      textstring             => x"444247"
   );

   -- Map gun coordinates (0-255 X, Y) to screen positions
   Gun1X_screen <= to_integer(to_unsigned(to_integer(videoout_settings.DisplayWidth * Gun1X), 18) (17 downto 8));
   Gun2X_screen <= to_integer(to_unsigned(to_integer(videoout_settings.DisplayWidth * Gun2X), 18) (17 downto 8));

   Gun1Y_screen <= '0' & Gun1Y_scanlines when videoout_settings.GPUSTAT_VerRes = '0' else Gun1Y_scanlines & '0';
   Gun2Y_screen <= '0' & Gun2Y_scanlines when videoout_settings.GPUSTAT_VerRes = '0' else Gun2Y_scanlines & '0';

   -- Lightgun crosshairs (currently single pixel to save resources)
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         if (video_ce = '1') then
            overlay_Gun1_ena <= '0';
            overlay_Gun2_ena <= '0';

            if (Gun1CrosshairOn = '1' and videoout_request.xpos = Gun1X_screen and to_integer(videoout_request.lineDisp) = Gun1Y_screen) then
               overlay_Gun1_ena <= '1';
            end if;

            if (Gun2CrosshairOn = '1' and videoout_request.xpos = Gun2X_screen and to_integer(videoout_request.lineDisp) = Gun2Y_screen) then
               overlay_Gun2_ena <= '1';
            end if;
         end if;
      end if;
   end process;
   
   overlay_ena <= overlay_error_ena or overlay_cd_ena or overlay_fps_ena or debugtextDbg_ena or overlay_Gun1_ena or overlay_Gun2_ena;
   
   overlay_data <= overlay_error_data when (overlay_error_ena = '1') else
                   overlay_cd_data    when (overlay_cd_ena = '1') else
                   overlay_fps_data   when (overlay_fps_ena = '1') else
                   debugtextDbg_data  when (debugtextDbg_ena = '1') else
                   x"0000FF"          when (overlay_Gun1_ena = '1') else
                   x"FFFF00"          when (overlay_Gun2_ena = '1') else
                   (others => '0');

end architecture;





