type BurritoMarkProps = {
  className?: string;
};

export function BurritoMark({ className }: BurritoMarkProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <circle cx="16" cy="16" r="16" fill="#1C1B18" />
      <g transform="rotate(-34 16 16)">
        <path
          d="M11 8.5h10a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3H11a3 3 0 0 1-3-3v-9a3 3 0 0 1 3-3Z"
          fill="#F6F4EE"
        />
        <path
          d="m8.7 19.2 7.3-5.4 7.3 5.4M9.3 10.2l6.7 4.9 6.7-4.9"
          stroke="#1C1B18"
          strokeWidth="1.35"
          strokeLinejoin="round"
        />
        <path
          d="M13.2 9.5c.3 1 .9 1.6 1.8 2M18.8 9.5c-.3 1-.9 1.6-1.8 2"
          stroke="#1C1B18"
          strokeWidth="1.15"
          strokeLinecap="round"
        />
      </g>
    </svg>
  );
}
