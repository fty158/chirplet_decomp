library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.axil_reg_file_pkg.all;

entity chirplet_decomp_top is
  port
  (
    s_axi_aclk    : in  std_logic;
    a_axi_aresetn : in  std_logic;

    s_axi_awaddr  : in  std_logic_vector(C_REG_FILE_ADDR_WIDTH-1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;

    s_axi_wdata   : in  std_logic_vector(C_REG_FILE_DATA_WIDTH-1 downto 0);
    s_axi_wstrb   : in  std_logic_vector(C_REG_FILE_DATA_WIDTH/8-1 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;

    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;

    s_axi_araddr  : in  std_logic_vector(C_REG_FILE_ADDR_WIDTH-1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;

    s_axi_rdata   : out std_logic_vector(C_REG_FILE_DATA_WIDTH-1 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic
  );
end entity;

architecture rtl of chirplet_decomp_top is

  constant C_SAMPLE_DWIDTH            : integer := 32; -- [bits], real + imaginary component
  constant C_NUM_PARALLEL_GENERATORS  : integer := 8;
  constant C_CHIRP2_XCORR_RATIO       : integer := 8;

  signal reset_n                      : std_logic;
  signal registers                    : reg_t;
  signal status_reg                   : std_logic_vector(31 downto 0);

  signal chirp_gen_num_samps_out      : std_logic_vector(15 downto 0);
  signal chirp_gen_din_ready          : std_logic;
  signal chirp_gen_dout               : std_logic_vector(C_SAMPLE_DWIDTH*C_NUM_PARALLEL_GENERATORS-1 downto 0);
  signal chirp_gen_dout_valid         : std_logic;
  signal chirp_gen_dout_ready         : std_logic;
  signal chirp_gen_dout_last          : std_logic;

  signal chrp2xcorr_din               : std_logic_vector(chirp_gen_dout'range);
  signal chrp2xcorr_din_valid         : std_logic;
  signal chrp2xcorr_din_ready         : std_logic;
  signal chrp2xcorr_din_last          : std_logic;
  signal chrp2xcorr_dout              : std_logic_vector(C_SAMPLE_DWIDTH*C_NUM_PARALLEL_GENERATORS*C_CHIRP2_XCORR_RATIO-1 downto 0);
  signal chrp2xcorr_dout_valid        : std_logic;
  signal chrp2xcorr_dout_ready        : std_logic;
  signal chrp2xcorr_dout_last         : std_logic;

  signal xcorr_din_real               : std_logic_vector((C_SAMPLE_DWIDTH/2)*64-1 downto 0);
  signal xcorr_din_imag               : std_logic_vector((C_SAMPLE_DWIDTH/2)*64-1 downto 0);
  signal xcorr_din_valid              : std_logic;
  signal xcorr_din_ready              : std_logic;
  signal xcorr_din_last               : std_logic;
  signal xcorr_dout                   : std_logic_vector(95 downto 0);
  signal xcorr_dout_valid             : std_logic;
  signal xcorr_dout_ready             : std_logic;
  signal xcorr_dout_last              : std_logic;

begin

  reset_n <= not reset;

  status_reg(31 downto 1) <= (others => '0');

  u_registers : entity work.axil_reg_file
    port map
    (
      s_axi_aclk    => clk,
      a_axi_aresetn => reset_n,

      s_STATUS      => 

      s_axi_awaddr  => s_axi_awaddr,
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,

      s_axi_wdata   => s_axi_wdata,
      s_axi_wstrb   => s_axi_wstrb,
      s_axi_wvalid  => s_axi_wvalid,
      s_axi_wready  => s_axi_wready,

      s_axi_bresp   => s_axi_bresp,
      s_axi_bvalid  => s_axi_bvalid,
      s_axi_bready  => s_axi_bready,

      s_axi_araddr  => s_axi_araddr,
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,

      s_axi_rdata   => s_axi_rdata,
      s_axi_rresp   => s_axi_rresp,
      s_axi_rvalid  => s_axi_rvalid,
      s_axi_rready  => s_axi_rready,

      registers_out => registers
    );

  chirp_gen_num_samps_out <= registers.CHIRP_GEN_NUM_SAMPS_OUT(15 downto 0);
  status_reg(0)           <= chirp_gen_din_ready;

  u_chirp_gen : entity work.chirplet_sig_gen_parallel_samps
    generic map
    (
      G_NUM_PARALLEL_GENERATORS => C_NUM_PARALLEL_GENERATORS,
      G_FILL_LSBS_FIRST         => true
    )
    port map
    (
      clk                       => clk,
      reset                     => reset,
      enable                    => enable,

      num_samps_out             => chirp_gen_num_samps_out,

      din_tau                   => registers.DIN_TAU,
      din_t_step                => registers.DIN_T_STEP,
      din_alpha1                => registers.DIN_ALPHA1,
      din_f_c                   => registers.DIN_F_C,
      din_alpha2                => registers.DIN_ALPHA2,
      din_phi                   => registers.DIN_PHI,
      din_beta                  => registers.DIN_BETA,
      din_valid                 => registers.DIN_BETA_wr_pulse,
      din_ready                 => chirp_gen_din_ready,

      dout                      => chirp_gen_dout,
      dout_valid                => chirp_gen_dout_valid,
      dout_ready                => chirp_gen_dout_ready,
      dout_last                 => chirp_gen_dout_last
    );

  chrp2xcorr_din        <= chirp_gen_dout;
  chrp2xcorr_din_valid  <= chirp_gen_dout_valid;
  chirp_gen_dout_ready  <= chrp2xcorr_din_ready;
  chrp2xcorr_din_last   <= chirp_gen_dout_last;

  u_chirp_gen_to_xcorr : symbol_expander
    generic map
    (
      G_DIN_WIDTH           => chirp_gen_dout'length,
      G_DOUT_OVER_DIN_WIDTH => C_CHIRP2_XCORR_RATIO,
      G_FILL_LSBS_FIRST     => true
    )
    port map
    (
      clk                   => clk,
      reset                 => reset,
      enable                => enable,

      din                   => chrp2xcorr_din,
      din_valid             => chrp2xcorr_din_valid,
      din_ready             => chrp2xcorr_din_ready,
      din_last              => chrp2xcorr_din_last,

      dout                  => chrp2xcorr_dout,
      dout_valid            => chrp2xcorr_dout_valid,
      dout_ready            => chrp2xcorr_dout_ready,
      dout_last             => chrp2xcorr_dout_last
    );

  xcorr_din_ready <= '1';

  g_xcorr_input : for i in 0 to 63 generate
    xcorr_din_real(i*16 to (i+1)*16-1) <= chrp2xcorr_dout((i+1)*32-16-1 downto (i)*32);
    xcorr_din_imag(i*16 to (i+1)*16-1) <= chrp2xcorr_dout((i+1)*32-1 downto (i)*32+16);
  end generate;

  u_xcorr : entity work.xcorr
    port map
    (
      clk             => clk,
      signalvalid     => xcorr_din_valid,
      chirpvalid      => '0',

      inputchirp      => xcorr_din_real,
      inputchirpimag  => xcorr_din_imag,
      inputsignal     => (others => '0'),
      inputsignalimag => (others => '0'),

      output          => xcorr_dout,
      outvalid        => xcorr_dout_valid
    );

end rtl;