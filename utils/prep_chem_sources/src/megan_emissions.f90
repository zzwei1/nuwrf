!###############################################################################!
!  CCATT-BRAMS/MCGA-CPTEC/WRF emission model    CPTEC/INPE                      !
!  Version 1.0.0: 12/nov/2010                                                   !
!  Coded by Saulo Freitas and Karla Longo                                       !
!  Contact: gmai@cptec.inpe.br - http://meioambiente.cptec.inpe.br              !
!###############################################################################!
!  Model of Emissions of Gases and Aerosols from Nature (MEGAN)                 !
!###############################################################################!

module megan_emissions
use netcdf
implicit none

integer, parameter :: maxnspecies = 200 , nspecies = 15 

integer, parameter ::         &
 CO		  =1   &
,CH4		  =2   &
,C2H4		  =3   &
,C2H6		  =4   &
,C3H6		  =5   &
,C3H8		  =6   &
,CH3OH		  =7   &
,CH2O		  =8   &
,CH3CHO		  =9   &
,ACETONE	  =10  &
,OTHKETONES	  =11  &
,TOLUENE	  =12  &
,ISOPRENE	  =13  &
,MONOTERPENES	  =14  &
,SESQUITERPENES	  =15

!---------------------------------------------------------------------------
character(LEN=25),dimension(nspecies),parameter :: netcdf_spc_name= &
! '1234567890123456789012345'
(/                           & 
  'CO                       '&
, 'methane                  '&
, 'ethene                   '&
, 'ethane                   '&
, 'propene                  '&
, 'propane                  '&
, 'methanol                 '&
, 'formaldehyde             '&
, 'acetaldehyde             '&
, 'acetone                  '&
, 'othKetones               '&
, 'toluene                  '&
, 'isoprene                 '&
, 'monoterpenes             '&
, 'sesquiterpenes           '&
/)

character(LEN=25),dimension(nspecies),parameter :: spc_name= &
! '1234567890123456789012345'
(/                           & 
  'CO                       '&
, 'CH4                      '&
, 'C2H4                     '&
, 'C2H6                     '&
, 'C3H6                     '&
, 'C3H8                     '&
, 'CH3OH                    '&
, 'CH2O                     '&
, 'CH3CHO                   '&
, 'ACETONE                  '&
, 'othKetones               '&
, 'C7H8                     '&
, 'C5H8                     '&
, 'C10H16                   '&
, 'C15H24                   '&
/)

type megan_vars   
	real, pointer, dimension(:,:,:)  :: src ! (lon,lat,time)
end type megan_vars

type (megan_vars), allocatable :: megan_g(:)

character(LEN=25) :: var_name

contains

!---------------------------------------------------------------

  subroutine alloc_megan(megan,n1,n2,n3)

    implicit none

    type (megan_vars),dimension(nspecies)  :: megan
    integer,intent(in) :: n1,n2,n3
    integer ispc
    
    do ispc=1,nspecies
     allocate (megan(ispc)%src(n1,n2,n3))
    enddo

    return
  end subroutine alloc_megan

  !---------------------------------------------------------------

  subroutine nullify_megan(megan)

    implicit none

    type (megan_vars),dimension(nspecies)  :: megan
    integer ispc

    do ispc=1,nspecies
       if (associated(megan(ispc)%src))    nullify (megan(ispc)%src)
    enddo

    return
  end subroutine nullify_megan

end module megan_emissions

!---------------------------------------------------------------
  subroutine mem_megan(n1,n2,n3)
    use megan_emissions
    implicit none
    integer i
    integer, intent(in) :: n1,n2,n3

    if(.not. allocated(megan_g)) allocate(megan_g(nspecies))
    !do i=1,nspecies
    ! if(associated(bioge_g(i)%src)) deallocate(bioge_g(i)%src)
    !enddo

    call nullify_megan(megan_g(:))      
    call alloc_megan  (megan_g(:),n1,n2,n3) 
  end subroutine mem_megan
! -----------------------------------------------------------

subroutine read_megan(iyear,imon,iday,ng,ngrids,n1,n2,n3,rlat,rlon,rland &
                     ,deltax,deltay,xt,yt,xm,ym,plat,plon)

use grid_dims_out, only: grid_type, bioge_data_dir
use megan_emissions

implicit none
!include 'netcdf.inc'
integer, parameter ::  nlon = 720, nlat = 360, nmonths = 12
integer, intent (in) :: iyear,imon,iday,ng,n1,n2,n3,ngrids
real, intent (in), dimension(n1,n2)  :: rlat,rlon,rland
real, intent (in) :: deltax,deltay
real,intent(in) ::  xt(n1), yt(n2),xm(n1), ym(n2)
integer :: ispc,im,i,k,iread,nc,ilaea,jlaea,kk,k1,k2,ii,i1,i2,j,imonx,var_id, ncid
integer :: ic,jc,j1,j2,nf
character*1 dummy
real longmegan(nlon),latmegan(nlat)
real, parameter ::   ilatn=0.5, ilonn=0.5
real lat,lon,plat,plon
real rrlat,rrlon,dlon1,dlon2,dlat1,dlat2,TX(nspecies), src_dummy(nlon,nlat,nmonths)
real,allocatable ,save :: RAWsrc(:,:,:,:)
character*240 prefix,suffix,filename(nspecies)
real, dimension(:) :: nclon(nlon), nclat(nlat)
character (len = *), parameter :: LAT_NAME = "lat"
character (len = *), parameter :: LON_NAME = "lon"
real, parameter ::                    &
        pi180    = 3.1415927 / 180.   &
    ,   r_earth  = 6370000.
integer :: lon_varid, lat_varid

if( .not. allocated (RAWsrc)) allocate(  RAWsrc(nlon,nlat,nmonths,nspecies) )

!lat e lon bioge (corner mais ao sul e mais a oeste)				      
do k=1,nlon
 longmegan(k)=-179.5 + (k-1)*ilonn
enddo
do i=1,nlat
 latmegan(i)= -89.5 + (i-1)*ilatn
enddo

if(ng == 1) then  ! need to read just one time
   prefix = 'MEGAN_nat_'
   suffix = '_2000_0.5x0.5.nc'
   var_name = 'emiss_anthro'   

   do ispc=1,nspecies
	nc=len_trim(netcdf_spc_name(ispc))
	filename(ispc)=trim(bioge_data_dir)//'/'//trim(prefix)//netcdf_spc_name(ispc)(1:nc)//trim(suffix)	
	
        if(ispc==1)print*,'----------------------------------------------------------------------'
 	print *,'opening MEGAN: ', trim(filename(ispc)(1:len_trim(filename(ispc)))),' - specie= ',trim(spc_name(ispc))

	call check( nf90_open(TRIM(filename(ispc)), NF90_NOWRITE, ncid) )
    
      	!print*, ncid, trim(spc_name(ispc))
	
	! Get the varids of the latitude and longitude coordinate variables.
  	call check( nf90_inq_varid(ncid, LAT_NAME, lat_varid) )
  	call check( nf90_inq_varid(ncid, LON_NAME, lon_varid) )
	
	! Read the latitude and longitude data.
  	call check( nf90_get_var(ncid, lat_varid, nclat) )
  	call check( nf90_get_var(ncid, lon_varid, nclon) )
	
	call check( nf90_inq_varid(ncid, trim(var_name), var_id) )

      	!print*,ncid,trim(var_name),var_id
      	!call FLUSH(6)
	
	call check( nf90_get_var(ncid, var_id, src_dummy) )	
	
	if (nclon(1) .gt. 0) then
		!print*, 'Reposicionando longitude de 0 para -180'
	
		call reposLon(src_dummy, nlon, nlat, nmonths)
		
		!print*, 'reposicionado com sucesso'	
	endif
	
	RAWsrc(:,:,:,ispc)=src_dummy(:,:,:)
        !print*,'Max-min val=',maxval(src_dummy(:,:,imon)),minval(src_dummy(:,:,imon))
	
	call check( nf90_close(ncid) )
   enddo ! nspecies  

endif ! ng==1

!--- performs the interpolation to model grid box
do i=1,n1
  do j=1,n2
      call get_index1(i,j,nlon,nlat,n1,n2,rlat,rlon,longmegan,latmegan &
                 ,ilatn, ilonn ,dlat1,dlat2,dlon1,dlon2,i1,j1,i2,j2,ic,jc)


      call interpol2(i,j,n1,n2,rlon,rlat,ic,jc,nlat,nlon,ilatn,ilonn   &
	           ,imon,nmonths,nspecies,RAWsrc,tx(1:nspecies))
! 
! TX is the value interpolated to the model grid box.
!-obs: the raw data is  the monthly mean and the units are in kg /(m^2 s)
      do ispc=1,nspecies
         megan_g(ispc)%src(i,j,1)=TX(ispc) * 86400. ! convert to kg/m2/day
      enddo    
  enddo
enddo 

!- deallocate memory that we do not need anymore    
if(ng==ngrids) deallocate (RAWsrc)

end subroutine read_megan

! -----------------------------------------------------------

subroutine createBin (var, var_name, nlon, nlat, time)
	implicit none

	integer, intent(in) :: nlon, nlat, time
	real, intent(in), dimension(nlon,nlat,time) :: var
	character(LEN=25), intent(in) :: var_name
	character(len=10) :: ci	
	integer :: i, j, t	
			
	print*, ' ---------------------------------------- '  
	print*, ' CRIANDO: ', trim(var_name)//'.gra    '   
	print*, ' ---------------------------------------- '

	open(19,file='./saidas/'//trim(var_name)//'.gra',access='direct', &
    		status='replace', recl=nlon*nlat*time*4, form='unformatted')
			
	write(19, rec=1) (((var(i,j,t),i=1,nlon),j=1,nlat),t=1,time)		
			
	close(19)
		
	print*, ' ---------------------------------------- '  
	print*, ' CRIANDO: ', trim(var_name)//'.ctl          '
	print*, ' ---------------------------------------- '

	open(19,file='./saidas/'//trim(var_name)//'.ctl',&
    		status='replace')    
	
	write(19,'(A)') 'dset ^'//trim(var_name)//'.gra'
	write(19,'(A)') 'undef -9999.'
	write(19,'(A)') 'title MEGAN Output'
	write(19,'(A)') 'xdef 720 linear  -179.75       0.5'
	write(19,'(A)') 'ydef 360 linear   -89.75       0.5'
	write(19,'(A)') 'zdef   1 levels 1'
	write(19,'(A)') 'tdef 12 linear 00:00z01jan2000         1mo'
	write(19,'(A)') 'vars 1'
	        
    	write(19,'(A)') trim(var_name)//'  0 99 - MEGAN           [kg/m^2 s]'
	
	write(19,'(A)') 'endvars'
	close (19)

	print*, ' ----------------------------------------- '  
	print*, ' ',trim(var_name)//'.ctl', ': CRIADO         '
	print*, ' ----------------------------------------- '					
			

end subroutine createBin 

! -----------------------------------------------------------

subroutine int2char(i, ci)
implicit none

integer, intent(in) :: i
character(len=10), intent(out) :: ci

if (i < 10 ) then
	write(ci, FMT='(I1)') i	
else
	write(ci, FMT='(I2)') i	
endif

end subroutine int2char

! -----------------------------------------------------------

subroutine reposLon(src_dummy, nlon, nlat, time)
implicit none

integer, intent(in) :: nlon, nlat, time
real, intent(inout) :: src_dummy(nlon, nlat, time)
real :: rtemp
integer :: i, j, t

do t=1, time
   do j=1,nlat
      do i=1,nlon/2
         rtemp                      = src_dummy(i,j,t)
         src_dummy(i,j,t)           = src_dummy((nlon/2)+i,j,t)
         src_dummy((nlon/2)+i,j,t)  = rtemp 
	 
      enddo
   enddo
enddo

end subroutine reposLon

!---------------------------------------------------------------
subroutine get_megan_indentity(spc_name,ident)
!use chem1_list
use megan_emissions, only :  megan_nspecies=>nspecies&
                            ,megan_spc_name=>spc_name

implicit none
integer isp
character (len=*), intent(in)  :: spc_name
integer          , intent(out) :: ident

do isp = 1,megan_nspecies
  ident=-1
  if(spc_name == megan_spc_name(isp)) then
      print*,'==>megan found for ',spc_name
      ident=isp
      return
   endif
enddo

!print*,'chem1-list specie ',trim(spc_name), ' does not match if any one of bioge'
!stop 444
end subroutine get_megan_indentity
!---------------------------------------------------------------


! -----------------------------------------------------------

!subroutine check(status)
!    integer, intent (in) :: status
    
!    if(status /= nf90_noerr) then 
!      print *, nf90_strerror(status)
!      stop "Stopped"
!    end if
!  end subroutine check

! -----------------------------------------------------------


